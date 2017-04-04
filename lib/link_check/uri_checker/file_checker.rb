module LinkCheck::UriChecker
  class FileChecker
    attr_reader :report

    def initialize(uri, options = {})
      @report = Report.new
    end

    def call
      report.add_error(:local_file, "Link is to a local file.")
      report
    end
  end
end
