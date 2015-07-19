#! /usr/bin/env ruby

require 'json'
require 'faraday'
require 'uri'

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

params = { labels: 'apt-whitelist' }
repo   = 'travis-ci/travis-ci'

response = conn.get "/repos/#{repo}/issues", params

tickets = JSON.parse(response.body)

# tickets.each do |t|
tickets.take(1).each do |t|
  unless match_data = /(?i:apt whitelist request for (?<package_name>[-\.\w]+))/.match(t['title'])
    puts "#{t['title']} is ambiguous"
    next
  end

  pkg = match_data[:package_name]
  issue_number = t["url"].split('/').last

  labels = t['labels']
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
      "branch"  => 'master',
      "config"  => {
        "env" => {
          "global" => ["PACKAGE=#{pkg}"]
        }
      }
    }
  }

  travis_response = travis_conn.post do |req|
    req.url "/repo/BanzaiMan%2Fapt-whitelist-checker/requests"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Travis-API-Version'] = '3'
    req.headers['Authorization'] = "token #{ENV["TRAVIS_TOKEN"]}"
    req.body = payload.to_json
  end

  if travis_response.success?
    # build request was accepted
    comment = "Run basic check to see if the package conatins setuid/setgid/seteuid calls. See URL"

    conn.post do |req|
      req.url "/repos/#{repo}/issues/#{issue_number}/comments"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
      req.body = { "body": comment }
    end

    conn.post do |req|
      req.url "/repos/#{repo}/issues/#{issue_number}/labels"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
      req.body = [ 'apt-whitelist-check-run' ]
    end
  end

end
