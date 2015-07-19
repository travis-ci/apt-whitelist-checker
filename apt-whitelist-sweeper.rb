#! /usr/bin/env ruby

require 'json'
require 'faraday'
require 'uri'

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

run_it = false

github_api = "https://api.github.com"
travis_api = 'https://api.travis-ci.org'

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

repo   = 'travis-ci/travis-ci'
next_page_url = "/repos/#{repo}/issues"

loop do
  response = conn.get do |req|
    req.url next_page_url
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.params['labels'] = 'apt-whitelist'
  end

  tickets = JSON.parse(response.body)

  tickets.each do |t|
    issue_number = t["url"].split('/').last

    unless match_data = /\A(?i:apt whitelist request for (?<package_name>\S+))\z/.match(t['title'])
      puts "'#{t['title']}' is ambiguous; #{issue_number}"
      next
    end

    pkg = match_data[:package_name]

    labels = t['labels'].tap {|x| puts "labels: #{x}"}
    if labels.any? { |l| l['name'] == 'apt-source-whitelist' }
      puts "#{pkg} needs source whitelisting"
      next
    end

    if labels.any? { |l| l['name'] == 'apt-whitelist-check-run' }
      puts "#{pkg} has been checked already"
      next
    end

    puts "#{t['title']}, #{issue_number}"

    message = "Run apt-source-whitelist check for #{pkg}; #{Time.now.utc.strftime('%Y-%m-%d-%H-%M-%S')}\n\nSee travis-ci/travis-ci##{issue_number}"

    payload = {
      "request"=> {
        "message" => message,
        "branch"  => 'default',
        "config"  => {
          "env" => {
            "global" => ["PACKAGE=#{pkg}"]
          }
        }
      }
    }

    puts "going to run test on #{pkg}"

    if run_it
      travis_response = travis_conn.post do |req|
        req.url "/repo/BanzaiMan%2Fapt-whitelist-checker/requests"
        req.headers['Content-Type'] = 'application/json'
        req.headers['Travis-API-Version'] = '3'
        req.headers['Authorization'] = "token #{ENV["TRAVIS_TOKEN"]}"
        req.body = payload.to_json
      end

      if travis_response.success?
        # build request was accepted
        comment = "Automated running a basic check to see if the package conatins suspicious setuid/setgid/seteuid calls."

        conn.post do |req|
          req.url "/repos/#{repo}/issues/#{issue_number}/comments"
          req.headers['Content-Type'] = 'application/json'
          req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
          req.body = { "body" => comment }
        end

        conn.post do |req|
          req.url "/repos/#{repo}/issues/#{issue_number}/labels"
          req.headers['Content-Type'] = 'application/json'
          req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
          req.body = [ 'apt-whitelist-check-run' ]
        end
      end
    end

  end

  break unless next_page_url = next_link_in_headers(response.headers).tap {|x| puts x}
end
