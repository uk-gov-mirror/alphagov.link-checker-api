require "rails_helper"

RSpec.describe LinkChecker do
  context "for different kinds of URIs" do
    subject { described_class.new(uri).call }

    shared_examples "has no errors" do
      it "should have no errors" do
        expect(subject.errors).to be_empty
      end
    end

    shared_examples "has an error" do |error|
      it "has an error of #{error}" do
        expect(subject.errors).to include(error)
        expect(subject.errors[error]).to_not be_empty
      end
    end

    shared_examples "does not have error" do |error|
      it "does not have an error of #{error}" do
        expect(subject.errors).to_not include(error)
      end
    end

    shared_examples "has no warnings" do
      it "should have no warnings" do
        expect(subject.warnings).to be_empty
      end
    end

    shared_examples "has a warning" do |warning|
      it "has a warning of #{warning}" do
        expect(subject.warnings).to include(warning)
        expect(subject.warnings[warning]).to_not be_empty
      end
    end

    shared_examples "does not have warning" do |warning|
      it "does not have an warning of #{warning}" do
        expect(subject.warnings).to_not include(warning)
      end
    end

    before do
      stub_request(:head, "https://www.gov.uk/ok").to_return(status: 200)

      stub_request(:post, "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=test")
        .to_return(status: 200, body: "{}")
    end

    context "invalid URI" do
      let(:uri) { "this is not a URI" }
      include_examples "has an error", "Invalid URL"
      include_examples "has no warnings"
    end

    context "URI with no scheme" do
      let(:uri) { "//test/test" }
      include_examples "has an error", "Invalid URL"
      include_examples "has no warnings"
    end

    context "URI with no host" do
      let(:uri) { "http:///" }
      include_examples "has an error", "Invalid URL"
      include_examples "has no warnings"
    end

    context "URI with an unsupported scheme" do
      let(:uri) { "mailto:test@test" }
      include_examples "has a warning", "Contact details"
      include_examples "has no errors"
    end

    context "URI with supported scheme" do
      let(:uri) { "https://www.gov.uk/ok" }
      include_examples "has no errors"
      include_examples "has no warnings"
    end

    context "TLD is risky" do
      let(:uri) { "https://www.gov.xxx" }
      before { stub_request(:head, uri).to_return(status: 200) }
      include_examples "has a warning", "Suspicious URL"
      include_examples "has no errors"
    end

    context "there are credentials in the URI" do
      let(:uri) { "https://username:password@www.gov.uk/ok" }
      include_examples "has a warning", "Login details in URL"
      include_examples "has no errors"
    end

    context "cannot connect to page" do
      let(:uri) { "http://www.not-gov.uk/connection_failed" }
      before { stub_request(:head, uri).to_raise(Faraday::ConnectionFailed) }
      include_examples "has an error", "Connection failed"
      include_examples "has no warnings"
    end

    context "SSL error" do
      let(:uri) { "http://www.not-gov.uk/ssl_error" }
      before { stub_request(:head, uri).to_raise(Faraday::SSLError) }
      include_examples "has an error", "Unsafe link"
      include_examples "has no warnings"
    end

    context "slow response" do
      let(:uri) { "http://www.not-gov.uk/slow_response" }
      before { stub_request(:head, uri).to_return(body: lambda { |_| sleep 2.6; "" }) }
      include_examples "has a warning", "Slow page load"
      include_examples "has no errors"
    end

    context "request timed out" do
      let(:uri) { "http://www.not-gov.uk/timeout" }
      before { stub_request(:head, uri).to_raise(Faraday::TimeoutError) }
      include_examples "has an error", "Timeout error"
      include_examples "has no warnings"
    end

    context "4xx status code" do
      let(:uri) { "http://www.not-gov.uk/404" }
      before { stub_request(:head, uri).to_return(status: 404) }
      include_examples "has an error", "404 error (page not found)"
      include_examples "has no warnings"
    end

    context "5xx status code" do
      let(:uri) { "http://www.not-gov.uk/500" }
      before { stub_request(:head, uri).to_return(status: 500) }
      include_examples "has an error", "500 (server error)"
      include_examples "has no warnings"
    end

    context "non-200 status code" do
      let(:uri) { "http://www.not-gov.uk/201" }
      before { stub_request(:head, uri).to_return(status: 201) }
      include_examples "has a warning", "Unusual response"
      include_examples "has no errors"
    end

    context "too many redirects" do
      let(:uri) { "http://www.not-gov.uk/too_many_redirects" }
      before do
        stub_request(:head, uri)
          .to_return(status: 301, headers: { "Location" => "/too_many_redirects_1" })

        20.times do |i|
          stub_request(:head, "http://www.not-gov.uk/too_many_redirects_#{i}")
            .to_return(status: 301, headers: { "Location" => "/too_many_redirects_#{i + 1}" })
        end
      end
      include_examples "has an error", "Too many redirects"
      include_examples "has a warning", "Slow page load"
    end

    context "multiple redirects" do
      before do
        stub_request(:head, uri)
          .to_return(status: 301, headers: { "Location" => "/multiple_redirects_1" })

        2.times do |i|
          stub_request(:head, "http://www.not-gov.uk/multiple_redirects_#{i}")
            .to_return(status: 301, headers: { "Location" => "/multiple_redirects_#{i + 1}" })
        end

        stub_request(:head, "http://www.not-gov.uk/multiple_redirects_2")
          .to_return(status: 301, headers: { "Location" => "https://www.gov.uk/ok" })
      end

      let(:uri) { "http://www.not-gov.uk/multiple_redirects" }
      include_examples "has a warning", "Slow page load"
      include_examples "has no errors"
    end

    context "cyclic redirects" do
      before do
        stub_request(:head, "http://www.not-gov.uk/cyclic")
          .to_return(status: 301, headers: { "Location" => "/cyclic1" })

        stub_request(:head, "http://www.not-gov.uk/cyclic1")
          .to_return(status: 301, headers: { "Location" => "/cyclic2" })

        stub_request(:head, "http://www.not-gov.uk/cyclic2")
          .to_return(status: 301, headers: { "Location" => "/cyclic" })
      end

      let(:uri) { "http://www.not-gov.uk/cyclic" }
      include_examples "has a warning", "Slow page load"
      include_examples "has an error", "Circular redirect"
      include_examples "does not have error", "Too many redirects"
    end

    context "a local file" do
      let(:uri) { "file://file.txt" }
      include_examples "has an error", "Not available online"
      include_examples "has no warnings"
    end

    context "meta rating suggests mature content" do
      before do
        stub_request(:head, "http://www.not-gov.uk/mature_content")
          .to_return(status: 200, headers: { "Content-Type" => "text/html" })

        stub_request(:get, "http://www.not-gov.uk/mature_content")
          .to_return(
            status: 200,
            body: "<meta name=rating value=mature>",
            headers: { "Content-Type" => "text/html" }
          )
      end

      let(:uri) { "http://www.not-gov.uk/mature_content" }
      include_examples "has a warning", "Possible adult content"
      include_examples "has no errors"
    end

    context "a URL detected by Google Safebrowser API" do
      let(:uri) { "http://malware.testing.google.test/testing/malware/" }
      before do
        stub_request(:head, uri).to_return(status: 200)
        stub_request(:post, "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=test")
          .to_return(status: 200, body: { matches: [{ threatType: "MALWARE" }] }.to_json)
      end
      include_examples "has a warning", "Flagged as dangerous"
      include_examples "has no errors"
    end
  end
end