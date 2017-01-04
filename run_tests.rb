#! /usr/bin/env ruby

require 'json'
require 'faraday'
require 'logger'
require 'uri'

unless ENV['GITHUB_OAUTH_TOKEN']
  puts "No GitHub token set"
  exit
end

@run_it    = !ENV['RUN'].to_s.empty?
github_api = "https://api.github.com"
travis_api = 'https://api.travis-ci.org'
owner      = 'travis-ci'
repo       = ENV['REPO'] || begin; puts "ENV['REPO'] undefined"; exit; end
SINCE      = '2015-07-01'
DISTS      = %w(precise trusty)

@logger = Logger.new(STDOUT)
log_level = ENV['LOG_LEVEL'] || 'warn'
@logger.level = Logger.const_get(log_level.upcase)

conn = Faraday.new(:url => github_api) do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.use Faraday::Response::Logger, Logger.new('/dev/null')
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end

def logger
  @logger
end

def next_link_in_headers(headers)
  # "<https://api.github.com/repositories/1420493/issues?labels=apt-whitelist&page=2>; rel=\"next\", <https://api.github.com/repositories/1420493/issues?labels=apt-whitelist&page=6>; rel=\"last\""
  next_link_text = headers['link'].split(',').find { |l| l.end_with? 'rel="next"' }
  if next_link_text && match_data = next_link_text.match(/<(?<next>[^>]+)>/)
    match_data[:next]
  end
end

def post_comment(conn:, issue:, comment:)
  unless @run_it
    loggeer.debug "action=comment comment=#{comment}"
    return
  end

  conn.post do |req|
    logger.debug "comments_url=#{issue['comments_url']}"
    req.url "#{URI.parse(issue['comments_url']).path}"
    req.headers['Content-Type'] = 'application/json'
    req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
    req.body = { "body" => comment }.to_json
  end
end

def add_labels(conn:, issue:, labels:, new_labels:)
  unless @run_it
    logger.debug "action=add_labels labels=#{new_labels.inspect}"
    return
  end

  Array(new_labels).each do |new_label|
    next if labels.any? { |l| l['name'] == new_label }

    conn.post do |req|
      logger.debug "url=#{issue['url']}"
      req.url "#{URI.parse(issue['url']).path}/labels"
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = "token #{ENV["GITHUB_OAUTH_TOKEN"]}"
      req.body = Array(new_label).to_json
    end
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

    logger.info "issue=#{t['html_url']}"
    logger.debug "title=#{title}"

    match_data = /\A(?i:APT(?<source> source)? whitelist request for (?<package_name>\S+)( in (?<dist>#{DISTS.join('|')}))?)\z/.match(title)

    next unless match_data

    if labels.any? { |l| l['name'] == 'apt-whitelist-check-run' || l['name'] == 'apt-whitelist-ambiguous' || l['name'] == 'apt-source-whitelist' }
      logger.debug "action=skip_check"
      next
    end

    pkg = match_data[:package_name]

    dist = (match_data[:dist] || 'precise').downcase

    if match_data[:source]
      logger.debug "message=source_request"
      add_labels(conn: conn, issue: t, labels: labels, new_labels: 'apt-source-whitelist')

      next
    end

    if pkg =~ /[\s:,]/ && pkg !~ /:i386/
      comment = <<-COMMENT
***This is an automated comment***

`#{pkg}` does not appear to a package name on which our automation process can handle.

APT packag request should be made for exactly one package, according to the form specified in
https://github.com/travis-ci/apt-package-whitelist#package-approval-process.

If the source package of your requested package contains other related packages, you do not
have to open another one for those.
(When in doubt, do.)
      COMMENT
      add_labels(conn: conn, issue: t, labels: labels, new_labels: 'apt-whitelist-ambiguous')

      post_comment(conn: conn, issue: t, comment: comment)

      next
    end

    logger.info "action=git_commit_create package=#{pkg} repo=#{repo} number=#{issue_number}"

    sleep 2 # comment out (or replace with a short sleep) when the script is good enough to run uninterrupted

    unless system("git checkout default")
      logger.warn "Unable to switch to `default` branch"
      next
    end

    system("sed -i -e 's/PACKAGE=.*/PACKAGE=#{pkg}/' .travis.yml")
    system("sed -i -e 's|ISSUE_REPO=.*|ISSUE_REPO=#{repo}|' .travis.yml")
    system("sed -i -e 's/ISSUE_NUMBER=.*/ISSUE_NUMBER=#{issue_number}/' .travis.yml")
    system("sed -i -e 's/DIST=.*/DIST=#{dist}/' .travis.yml")

    comment = "Run test for #{owner}/#{repo}##{issue_number} in dist #{dist}. (#{pkg})"

    system("git add .travis.yml")
    system("git commit --allow-empty -m '#{comment}'")
    system("git push origin default")

  end

  break unless next_page_url = next_link_in_headers(list_response.headers)
end
