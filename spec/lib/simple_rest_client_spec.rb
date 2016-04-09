require 'simple_rest_client'
require 'stringio'

RSpec.describe SimpleRESTClient do
  let(:address) { 'example.com' }
  let(:path) { '/test_path' }
  let(:base_path) { '/base_path' }
  let(:query) { {query_parameter: 'query_value'} }
  let(:base_query) { {base_query_parameter: 'base_query_value'} }
  let(:headers) { {header_name: 'header_value'} }
  let(:base_headers) { {base_header_name: 'base_header_value'} }
  let(:body) { 'request_body' }
  let(:body_stream_text) { "body\n" * 10 }
  def body_stream text
    StringIO.new(text, 'r')
  end
  let(:username) { 'username' }
  let(:password) { 'password' }
  let(:default_net_http_headers) { Net::HTTP::Get.new('/').to_hash }
  subject { described_class.new(address: address) }
  context '#initialize' do
    context '#port' do
      context 'defaults' do
        context 'HTTP' do
          it 'is set to 80' do
            expect(subject.port).to eq(80)
          end
        end
        context 'HTTPS' do
          subject do
            described_class.new(
              address: address,
              net_http_start_opt: {
                use_ssl: true,
              }
            )
          end
          it 'is set to 443' do
            expect(subject.port).to eq(443)
          end
        end
      end
    end
    context '#net_http_start_opt' do
      context 'defaults' do
        context 'not specified' do
          it 'is set to DEFAULT_NET_HTTP_START_OPT' do
            expect(subject.net_http_start_opt).to eq(described_class.const_get(:DEFAULT_NET_HTTP_START_OPT))
          end
        end
        context 'port is 443' do
          let(:port) { 443 }
          context ':use_ssl not specified' do
            subject do
              described_class.new(address: address, port: port)
            end
            it 'sets :use_ssl' do
              expect(subject.net_http_start_opt[:use_ssl]).to eq(true)
            end
          end
          context ':use_ssl specified' do
            let(:use_ssl_value) { false }
            subject do
              described_class.new(
                address: address,
                port: port,
                net_http_start_opt: {
                  use_ssl: use_ssl_value
                }
              )
            end
            it 'keeps :use_ssl value' do
              expect(subject.net_http_start_opt[:use_ssl]).to eq(use_ssl_value)
            end
          end
        end
      end
    end
  end
  context '#base_path' do
    context 'unset' do
      it 'does requests without base_path prefix' do
        request = stub_request(:get, "#{address}#{path}")
        subject.send(:get, path)
        expect(request).to have_been_requested
      end
    end
    context 'set' do
      subject do
        described_class.new(address: address, base_path: base_path)
      end
      it 'prefix requests with base_path' do
        request = stub_request(:get, "#{address}#{base_path}#{path}")
        subject.send(:get, path)
        expect(request).to have_been_requested
      end
    end
  end
  context '#base_query' do
    context 'unset' do
      it 'does not change query' do
        request = stub_request(:get, "#{address}#{path}")
          .with(query: {})
        subject.send(:get, path)
        expect(request).to have_been_requested
      end
    end
    context 'set' do
      subject do
        described_class.new(address: address, base_query: base_query)
      end
      context 'conflicting parameters' do
        it 'raises ArgumentError' do
          expect do
            subject.send(:get, path, query: base_query)
          end.to raise_error(
            ArgumentError,
            /passed query parameters conflict with base_query parameters/i
          )
        end
      end
      it 'sets base_query parameters' do
        request = stub_request(:get, "#{address}#{path}")
          .with(query: base_query)
        subject.send(:get, path)
        expect(request).to have_been_requested
      end
    end
  end
  context 'base_headers' do
    context 'unset' do
      it 'does not send extra headers' do
        request = stub_request(:get, "#{address}#{path}")
          .with(headers: default_net_http_headers)
        subject.send(:get, path)
        expect(request).to have_been_requested
      end
    end
    context 'set' do
      subject do
        described_class.new(address: address, base_headers: base_headers)
      end
      context 'conflicting parameters' do
        it 'raises ArgumentError' do
          expect do
            subject.send(:get, path, headers: base_headers)
          end.to raise_error(
            ArgumentError,
            /passed headers conflict with base_headers/i
          )
        end
      end
      it 'sets base_headers' do
        request = stub_request(:get, "#{address}#{path}")
          .with(headers: default_net_http_headers.merge(headers))
        subject.send(:get, path, headers: headers)
        expect(request).to have_been_requested
      end
    end
  end
  context '#username and #password' do
    context 'unset' do
      it 'does not use basic auth' do
        request = stub_request(:get, "#{address}#{path}")
        subject.send(:get, path, headers: headers)
        expect(request).to have_been_requested
      end
    end
    context 'set' do
      subject do
        described_class.new(
          address: address,
          username: username,
          password: password
        )
      end
      it 'uses basic auth' do
        request = stub_request(:get, "#{username}:#{password}@#{address}#{path}")
        subject.send(:get, path, headers: headers)
        expect(request).to have_been_requested
      end
    end
  end
  context 'HTTP Methods' do
    let(:request_parameters) { {query: query, headers: headers} }
    [
      :get,
      :head,
      :post,
      :put,
      :delete,
      :options,
      :trace,
      :patch
    ].each do |http_method|
      request_has_body = Net::HTTP.const_get(http_method.downcase.capitalize)
        .const_get(:REQUEST_HAS_BODY)
      if request_has_body
        context "#{http_method.upcase}" do
          context 'static body' do
            it "can perform #{http_method.upcase} requests" do
              request_parameters.merge!(body: body)
              request = stub_request(http_method, "#{address}#{path}")
                .with(request_parameters)
              expect(subject)
                .to receive(:request)
                .with(http_method, path, request_parameters)
                .and_call_original
              subject.send(http_method, path, request_parameters)
              expect(request).to have_been_requested
            end
          end
          context 'streaming body' do
            it "can perform #{http_method.upcase} requests" do
              request = stub_request(http_method, "#{address}#{path}")
                .with(request_parameters.merge(body: body_stream_text))
              body_stream_arg = body_stream(body_stream_text)
              expect(subject)
                .to receive(:request)
                .with(
                  http_method,
                  path,
                  request_parameters.merge(body_stream: body_stream_arg)
                )
                .and_call_original
              subject.send(
                http_method,
                path,
                request_parameters.merge(body_stream: body_stream_arg)
              )
              expect(request).to have_been_requested
            end
          end
          context 'no body' do
            it "can perform #{http_method.upcase} requests" do
              request = stub_request(http_method, "#{address}#{path}")
              .with(request_parameters)
              expect(subject)
              .to receive(:request)
              .with(http_method, path, request_parameters)
              .and_call_original
              subject.send(http_method, path, request_parameters)
              expect(request).to have_been_requested
            end
          end
        end
      else
        it "can perform #{http_method.upcase} requests" do
          request = stub_request(http_method, "#{address}#{path}")
            .with(request_parameters)
          expect(subject)
            .to receive(:request)
            .with(http_method, path, request_parameters)
            .and_call_original
          subject.send(http_method, path, request_parameters)
          expect(request).to have_been_requested
        end
      end
    end
  end
  context '#request' do
    let(:http_method) { :mkcol }
    it 'can perform generic requests' do
      request = stub_request(http_method, "#{address}#{path}")
      subject.request(http_method, path)
      expect(request).to have_been_requested
    end
    context 'expected_status_code' do
      shared_examples :expected_status_code do |expected_status_code:, unexpected_status_code:, real_status_code:|
        context "expected #{expected_status_code}, got #{real_status_code}" do
          it 'does not raise' do
            request = stub_request(:get, "#{address}#{path}")
              .to_return(status: real_status_code)
            expect do
              subject.get(path, expected_status_code: expected_status_code)
            end.not_to raise_error
            expect(request).to have_been_requested
          end
        end
        context "expected #{unexpected_status_code}, got #{real_status_code}" do
          it 'raises' do
            request = stub_request(:get, "#{address}#{path}")
            .to_return(status: real_status_code)
            expect do
              subject.get(path, expected_status_code: unexpected_status_code)
            end.to raise_error(described_class.const_get(:UnexpectedStatusCode))
            expect(request).to have_been_requested
          end
        end
      end
      context 'not specified' do
        it 'defaults to :successful' do
          request = stub_request(:get, "#{address}#{path}")
            .to_return(status: 202)
          expect do
            subject.get(path)
          end.not_to raise_error
          expect(request).to have_been_requested
        end
        it 'raises for non :successful' do
          request = stub_request(:get, "#{address}#{path}")
          .to_return(status: 300)
          expect do
            subject.get(path)
          end.to raise_error(described_class.const_get(:UnexpectedStatusCode))
          expect(request).to have_been_requested
        end
      end
      context 'specified' do
        context 'as number' do
          include_examples(
            :expected_status_code,
            expected_status_code:   200,
            unexpected_status_code: 202,
            real_status_code:       200
          )
        end
        context 'as array' do
          include_examples(
            :expected_status_code,
            expected_status_code:   [200, 202],
            unexpected_status_code: 201,
            real_status_code:       200
          )
        end
        context 'as symbol' do
          [
            [:informational, 201, 100],
            [:successful,    301, 202],
            [:redirection,   201, 301],
            [:client_error,  201, 400],
            [:server_error,  201, 503],
          ].each do |args|
            expected_status_code, unexpected_status_code, real_status_code = *args
            context ":#{expected_status_code}" do
              include_examples(
                :expected_status_code,
                expected_status_code:   expected_status_code,
                unexpected_status_code: unexpected_status_code,
                real_status_code:       real_status_code
              )
            end
          end
        end
        context 'as class' do
          [
            [Net::HTTPInformation, 200, 100],
            [Net::HTTPSuccess,     100, 200],
            [Net::HTTPRedirection, 100, 300],
            [Net::HTTPClientError, 100, 400],
            [Net::HTTPServerError, 100, 500],
          ].each do |args|
            expected_status_code, unexpected_status_code, real_status_code = *args
            context "#{expected_status_code}" do
              include_examples(
                :expected_status_code,
                expected_status_code:   expected_status_code,
                unexpected_status_code: unexpected_status_code,
                real_status_code:       real_status_code
              )
            end
          end
        end
        context 'nil' do
          it 'ignores status code' do
            request = stub_request(:get, "#{address}#{path}")
              .to_return(status: 500)
            expect do
              subject.get(path, expected_status_code: nil)
            end.not_to raise_error
            expect(request).to have_been_requested
          end
        end
      end
    end
    it 'passes net_http_start_opt to Net::HTTP.start' do
      stub_request(http_method, "#{address}#{path}")
      expect(Net::HTTP)
        .to receive(:start)
        .with(any_args, subject.net_http_start_opt)
        .and_call_original
      subject.request(http_method, path)
    end
    # Test workarounds for https://bugs.ruby-lang.org/issues/2567
    context 'response body encoding' do
      let(:utf8_text) { 'fábio' }
      let(:body_encoding) { 'ISO-8859-1' }
      let(:raw_body) do
        utf8_text.encode(body_encoding).force_encoding('US-ASCII')
      end
      context 'charset at headers' do
        before(:example) do
          @request = stub_request(:get, "#{address}:#{path}")
            .to_return(
              body: raw_body,
              headers: default_net_http_headers.merge(
                "Content-Type" => "text/html; charset=#{body_encoding}"
              )
            )
        end
        after(:example) do
          expect(@response_body.encoding.to_s).to eq(body_encoding)
          expect(@response_body.encode('UTF-8')).to eq(utf8_text)
        end
        it 'Net::HTTPResponse#body' do
          @response_body = subject.request(:get, path).body
        end
        it 'Net::HTTPResponse#read_body' do
          @response_body = subject.request(:get, path).read_body
        end
        it 'Net::HTTPResponse#read_body (with block)' do
          @response_body = nil
          subject.request(:get, path) do |response|
            response.read_body do |chunk|
              if @response_body
                @response_body << chunk
              else
                @response_body = chunk
              end
            end
          end
        end
      end
      context 'no charset at headers defaults to ASCII-8BIT' do
        before(:example) do
          @request = stub_request(:get, "#{address}:#{path}")
            .to_return(
              body: raw_body,
              headers: default_net_http_headers.merge(
                "Content-Type" => "text/html"
              )
            )
        end
        after(:example) do
          expect(@response_body.encoding.to_s).to eq('ASCII-8BIT')
          expect(@response_body.b).to eq(raw_body.b)
        end
        it 'Net::HTTPResponse#body' do
          @response_body = subject.request(:get, path).body
        end
        it 'Net::HTTPResponse#read_body' do
          @response_body = subject.request(:get, path).read_body
        end
        it 'Net::HTTPResponse#read_body (with block)' do
          @response_body = nil
          subject.request(:get, path) do |response|
            response.read_body do |chunk|
              if @response_body
                @response_body << chunk
              else
                @response_body = chunk
              end
            end
          end
        end
      end
    end
  end
end
