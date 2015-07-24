#! /usr/bin/env ruby

require 'json'
require 'faraday'
require 'logger'

@run_it    = !ENV['RUN'].to_s.empty?
github_api = "https://api.github.com"
travis_api = 'https://api.travis-ci.org'
owner      = 'travis-ci'
repo       = ENV['REPO'] || begin; puts "ENV['REPO'] undefined"; exit; end
SINCE      = '2015-07-01'

conn = Faraday.new(:url => github_api) do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.use Faraday::Response::Logger, Logger.new('github.log')
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
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

def post_comment(conn:, owner:, repo:, issue:, comment:)
  unless @run_it
    puts ">> Would have commented: #{comment}"
    return
  end

  conn.post do |req|
    req.url "/repos/#{owner}/#{repo}/issues/#{issue}/comments"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.body = { "body" => comment }.to_json
  end
end

def add_label(conn:, owner:, repo:, issue:, labels:)
  unless @run_it
    puts ">> Would have added labels #{labels.inspect}"
    return
  end

  conn.post do |req|
    req.url "/repos/#{owner}/#{repo}/issues/#{issue}/labels"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.body = Array(labels).to_json
  end
end

next_page_url = "/repos/#{owner}/#{repo}/issues"

loop do
  list_response = conn.get do |req|
    req.url next_page_url
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.params['sort'] = 'created'
    req.params['direction'] = 'asc'
  # req.params['since'] = SINCE
  end

  tickets = JSON.parse(list_response.body)

  tickets.each do |t|
    issue_number = t["url"].split('/').last

    labels = t['labels']
    title  = t['title'].strip

    puts "checking #{t['html_url']}"
    puts "title: #{title}"

    match_data = /\A(?i:APT(?<source> source)? whitelist request for (?<package_name>.+))\z/.match(title)

    next unless match_data

    if labels.any? { |l| l['name'] == 'apt-whitelist-check-run' }
      puts ">> We have run a check already\n"
      next
    end

    pkg = match_data[:package_name]

    if match_data[:source]
      puts ">> source request detected"
      if labels.none? {|l| l['name'] == 'apt-source-whitelist'}
        add_label(conn: conn, owner: owner, repo: repo, issue: issue_number, labels: 'apt-source-whitelist')
      end

      next
    end

    if pkg =~ /[\s:,]/ && pkg !~ /:i386/
      comment = <<-COMMENT
`#{pkg}` does not appear to a package name on which our automation process can handle.

APT packag request should be made for exactly one package, according to the form specified in
https://github.com/travis-ci/apt-package-whitelist#package-approval-process.

If the source package of your requested package contains other related packages, you do not
have to open another one for those.
(When in doubt, do.)
      COMMENT
      if labels.none? {|l| l['name'] == 'apt-whitelist-ambiguous'}
        add_label(conn: conn, owner: owner, repo: repo, issue: issue_number, labels: 'apt-whitelist-ambiguous')
      end

      post_comment(conn: conn, owner: owner, repo: repo, issue: issue_number, comment: comment)

      next
    end

    puts "\n\n About to create git commit with PACKAGE=#{pkg} ISSUE_REPO=#{repo} ISSUE_NUMBER=#{issue_number}"

    gets # comment out (or replace with a short sleep) when the script is good enough to run uninterrupted

    system("sed -i.bak1 -e 's/PACKAGE=.*/PACKAGE=#{pkg}/' .travis.yml")
    system("sed -i.bak2 -e 's|ISSUE_REPO=.*|ISSUE_REPO=#{repo}|' .travis.yml")
    system("sed -i.bak3 -e 's/ISSUE_NUMBER=.*/ISSUE_NUMBER=#{issue_number}/' .travis.yml")

    comment = "Run test for #{owner}/#{repo}##{issue_number}."

    system("git add .travis.yml")
    system("git commit -m '#{comment}'")
    system("git push origin default")

  end

  break unless next_page_url = next_link_in_headers(list_response.headers)
end
