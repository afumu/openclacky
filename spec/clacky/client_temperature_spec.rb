# frozen_string_literal: true

require "spec_helper"

RSpec.describe Clacky::Client, "simple request temperature" do
  let(:client) do
    Clacky::Client.new("test", base_url: "https://unused.invalid/v1",
                            model: "deepseek_v4_flash_lite", api_format: "openai-completions")
  end

  [0, nil].each do |temperature|
    it "#{temperature.nil? ? 'omits an unspecified temperature' : 'preserves zero temperature'} in the HTTP body" do
      bodies = []
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("chat/completions") do |env|
          bodies << JSON.parse(env.body)
          [200, { "Content-Type" => "application/json" },
           { choices: [{ message: { content: "none" } }] }.to_json]
        end
      end
      connection = Faraday.new { |builder| builder.adapter :test, stubs }
      allow(client).to receive(:openai_connection).and_return(connection)
      options = { model: "deepseek_v4_flash_lite", max_tokens: 192, reasoning_effort: "minimal" }
      options[:temperature] = temperature unless temperature.nil?

      result = client.send_messages([{ role: "user", content: "Build a comic generator" }], **options)

      expect(result).to eq("none")
      expect(bodies.size).to eq(1)
      expect(bodies.first).to include("model" => options[:model], "max_tokens" => 192)
      if temperature.nil?
        expect(bodies.first).not_to have_key("temperature")
      else
        expect(bodies.first).to include("temperature" => 0)
      end
      stubs.verify_stubbed_calls
    end
  end
end
