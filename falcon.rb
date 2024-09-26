#!/usr/bin/env -S falcon host

load :rack

hostname = File.basename(__dir__)
port = ENV.fetch("PORT") { 3000 }

service hostname do
  include Falcon::Environment::Rack

  count ENV.fetch('WEB_CONCURRENCY', 1).to_i
  preload 'preload.rb'
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port}").with(protocol: Async::HTTP::Protocol::HTTP11)
end
