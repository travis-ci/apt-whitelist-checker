#! /usr/bin/env ruby

require 'json'
require 'faraday'
require 'uri'

@run_it    = !ENV['RUN'].to_s.empty?
github_api = "https://api.github.com"
travis_api = 'https://api.travis-ci.org'
repo       = 'travis-ci/travis-ci'

conn = Faraday.new(:url => github_api) do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end

travis_conn = Faraday.new(:url => travis_api) do |faraday|
  faraday.request :url_encoded
  faraday.response :logger
  faraday.adapter Faraday.default_adapter
end

def next_link_in_headers(headers)
  # "<https://api.github.com/repositories/1420493/issues?labels=apt-whitelist&page=2>; rel=\"next\", <https://api.github.com/repositories/1420493/issues?labels=apt-whitelist&page=6>; rel=\"last\""
  next_link_text = headers['link'].split(',').find { |l| l.end_with? 'rel="next"' }
  if next_link_text
    match_data = next_link_text.match(/<(?<next>[^>]+)>/)
    if match_data
      match_data[:next]
    end
  end
end

def reject_label(conn:, repo:, issue:, labels:, label:, reason:, should_comment: false)
  rejected = false
  if labels.any? { |l| l['name'] == label }
    puts reason
    rejected = true
  else
    return
  end

  if should_comment
    post_comment(conn: conn, repo: repo, issue: issue, comment: "Did not run automated check because #{reason}")
    add_label(conn: conn, repo: repo, issue: issue, label: 'apt-whitelist-check-commented')
  end

  rejected
end

def post_comment(conn:, repo:, issue:, comment:)
  unless @run_it
    puts "Would have commented: #{comment}"
    return
  end

  conn.post do |req|
    req.url "/repos/#{repo}/issues/#{issue}/comments"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.body = { "body" => comment }.to_json
  end
end

def add_label(conn:, repo:, issue:, label:)
  unless @run_it
    puts "Would have added label #{label}"
    return
  end

  conn.post do |req|
    req.url "/repos/#{repo}/issues/#{issue}/labels"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.body = [ label ].to_json
  end
end

next_page_url = "/repos/#{repo}/issues"

loop do
  response = conn.get do |req|
    req.url next_page_url
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.params['sort'] = 'created'
    req.params['direction'] = 'asc'
  end

  tickets = JSON.parse(response.body)

  tickets.each do |t|
    issue_number = t["url"].split('/').last

    labels = t['labels']
    title  = t['title'].strip

    next if labels.any? { |l| l['name'] == 'apt-whitelist-check-run' || l['name'] == 'apt-whitelist-check-commented' }

    next unless match_data = /\A(?i:apt(?<source> source)? whitelist request for (?<package_name>.+))\z/.match(title)

    labels.none? { |l| l['name'] == label } && add_label(conn: conn, repo: repo, issue: issue_number, label: 'apt-whitelist')

    pkg = match_data[:package_name]
    if pkg.include? ' ' && labels.none? { |l| l['name'] == 'apt-whitelist-ambiguous' }
      add_label(conn: conn, repo: repo, issue: issue_number, label: 'apt-whitelist-ambiguous')
    end

    if match_data[:source] && labels.none? { |l| l['name'] == 'apt-source-whitelist' }
      add_label(conn: conn, repo: repo, issue: issue_number, label: 'apt-source-whitelist')
    end

    ## refresh ticket data
    response = conn.get do |req|
      req.url "/repos/#{repo}/issues/#{issue_number}"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    end
    ticket = JSON.parse(response.body)
    labels = ticket['labels']

    reject_label(
      conn: conn, repo: repo, issue: issue_number, labels: labels, label: 'apt-source-whitelist', reason: "'#{pkg}' needs source whitelisting", should_comment: true
    )
    reject_label(
      conn: conn, repo: repo, issue: issue_number, labels: labels, label: 'trusty', reason: "'#{pkg}' needs trusty", should_comment: true
    )
    reject_label(
      conn: conn, repo: repo, issue: issue_number, labels: labels, label: 'apt-whitelist-ambiguous', reason: "title '#{title}' is ambiguous. Please specify only one.", should_comment: true
    )
    reject_label(
      conn: conn, repo: repo, issue: issue_number, labels: labels, label: 'apt-whitelist-check-run', reason: "'#{pkg}' has been checked already"
    )

    puts "#{title}, #{issue_number}; going to run test on #{pkg}"
    next unless @run_it

    next if labels.any? { |l| l['name'] == 'apt-source-whitelist' || l['name'] == 'trusty' || l['name'] == 'apt-whitelist-ambiguous' || l['name'] == 'apt-whitelist-check-commented' }

    # prepare Travis CI build request payload
    message = "Run apt-package-whitelist check for #{pkg}; #{Time.now.utc.strftime('%Y-%m-%d-%H-%M-%S')}\n\nSee travis-ci/travis-ci##{issue_number}"

    payload = {
      "request"=> {
        "message" => message,
        "branch"  => 'default',
        "config"  => {
          "env" => {
            "global" => ["PACKAGE=#{pkg}","ISSUE_NUMBER=#{issue_number}"],
          }
        }
      }
    }

    puts "Starting build for #{pkg}; https://github.com/travis-ci/travis-ci/issues/#{issue_number}. Run it (y/n)?"
    answer = gets
    next unless answer =~ /^yes/i

    travis_response = travis_conn.post do |req|
      req.url "/repo/travis-ci%2Fapt-whitelist-checker/requests"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Travis-API-Version'] = '3'
      req.headers['Authorization'] = "token #{ENV["TRAVIS_TOKEN"]}"
      req.body = payload.to_json
    end

    started = false

    begin
      if travis_response.success?
        # build request was accepted

        comment = "Running a basic check to see if the package conatins suspicious setuid/setgid/seteuid calls."

        post_comment(conn: conn, repo: repo, issue: issue_number, comment: comment)

        add_label(conn: conn, repo: repo, issue: issue_number, label: 'apt-whitelist-check-run')

        started = true
      else
        sleep 300
      end
    end while ! started

  end

  break unless next_page_url = next_link_in_headers(response.headers).tap {|x| puts x}
end
