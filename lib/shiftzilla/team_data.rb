require 'shiftzilla/release_data'

module Shiftzilla
  class TeamData
    attr_reader :name

    def initialize(tname,config=nil)
      @name         = tname
      @config       = config
      @release_data = {}
    end

    def title
      @title ||= (@name == '_overall' ? @config.org_title : @name)
    end

    def prefix
      @prefix ||= (@name == '_overall' ? "all_org" : "team_#{@name.tr(' ?()', '')}")
    end

    def file
      @file ||= "#{ @name == '_overall' ? 'index' : prefix }.html"
    end

    def has_release_data?(release)
      @release_data.has_key?(release.name)
    end

    def get_release_data(release)
      rname = release.name
      unless @release_data.has_key?(rname)
        @release_data[rname] = Shiftzilla::ReleaseData.new(release)
      end
      @release_data[rname]
    end
  end
end
