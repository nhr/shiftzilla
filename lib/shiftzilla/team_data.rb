require 'shiftzilla/release_data'

module Shiftzilla
  class TeamData

    def initialize(tname)
      @name         = tname
      @release_data = {}
    end

    def title
      @title ||= (@name == '_overall' ? 'Atomic / OpenShift' : @name)
    end

    def prefix
      @prefix ||= (@name == '_overall' ? "all_aos" : "team_#{@name.tr(' ?()', '')}")
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
