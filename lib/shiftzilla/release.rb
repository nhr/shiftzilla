require 'shiftzilla/milestones'

module Shiftzilla
  class Release
    attr_reader :name, :targets, :milestones, :default, :token

    def initialize(release,builtin=false)
      @name       = release['name']
      @token      = @name.tr(' .', '_')
      @targets    = release['targets']
      @default    = release.has_key?('default') ? release['default'] : false
      @builtin    = builtin
      @milestones = nil
      if release.has_key?('milestones')
        @milestones = Shiftzilla::Milestones.new(release['milestones'])
      end
    end

    def uses_milestones?
      return @milestones.nil? ? false : true
    end

    def built_in?
      @builtin
    end

    def no_tgt_rel?
      if @targets.length == 1 and @targets[0] == '---'
        return true
      end
      false
    end
  end
end