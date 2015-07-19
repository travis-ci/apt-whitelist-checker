require 'json'
require 'faraday'

desc "Build up build request payload file based on information in .travis.yml"
task :build, [:package,:number] do |t, args|
  package = args[:package]
  issue_number = args[:number]

  unless ENV["TRAVIS_TOKEN"]
    puts "Env var TRAVIS_TOKEN not set"
    exit 1
  end

  travis_api = 'https://api.travis-ci.org'

  travis_conn = Faraday.new(:url => travis_api) do |faraday|
    faraday.request :url_encoded
    faraday.response :logger
    faraday.adapter Faraday.default_adapter
  end

  message = "Run apt-source-whitelist check for #{package}; #{Time.now.utc.strftime('%Y-%m-%d-%H-%M-%S')}\n\nSee travis-ci/travis-ci##{issue_number}"

  payload = {
    "request"=> {
      "message" => message,
      "branch"  => 'default',
      "config"  => {
        "env" => {
          "global" => ["PACKAGE=#{package}"]
        }
      }
    }
  }

  response = travis_conn.post do |req|
    req.url "/repo/BanzaiMan%2Fapt-whitelist-checker/requests"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Travis-API-Version'] = '3'
    req.headers['Authorization'] = "token #{ENV["TRAVIS_TOKEN"]}"
    req.body = payload.to_json
  end

  puts response.body
end
