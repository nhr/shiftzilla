require 'date'
require 'shiftzilla/group'
require 'shiftzilla/release'
require 'shiftzilla/source'
require 'shiftzilla/team'

module Shiftzilla
  class Config
    attr_reader :teams, :groups, :sources, :releases, :ssh

    def initialize
      @teams    = []
      @groups   = []
      @sources  = []
      group_map = {}
      cfg_file['Groups'].each do |group|
        gobj = Shiftzilla::Group.new(group)
        @groups << gobj
        group_map[gobj.id] = gobj
      end
      cfg_file['Teams'].each do |team|
        @teams << Shiftzilla::Team.new(team,group_map)
      end
      cfg_file['Sources'].each do |sid,sinfo|
        @sources << Shiftzilla::Source.new(sid,sinfo)
      end
      # Always track a release for bugs with no target release
      @releases = [Shiftzilla::Release.new({ 'name' => '"---"', 'targets' => ['---'] },true)]
      cfg_file['Releases'].each do |release|
        @releases << Shiftzilla::Release.new(release)
      end
      @releases << Shiftzilla::Release.new({ 'name' => 'All', 'targets' => [] },true)
      @ssh = {
        :host => cfg_file['SSH']['host'],
        :path => cfg_file['SSH']['path'],
        :url  => cfg_file['SSH']['url'],
      }
    end

    def earliest_milestone
      milestone_boundaries[:earliest]
    end

    def latest_milestone
      milestone_boundaries[:latest]
    end

    def team(tname)
      @teams.select{ |t| t.name == tname }[0]
    end

    def add_ad_hoc_team(tinfo)
      @teams << Shiftzilla::Team.new(tinfo,{},true)
    end

    def release(rname)
      @releases.select{ |r| r.name == rname }[0]
    end

    def release_by_target(tgt)
      return target_map[tgt]
    end

    private

    def target_map
      @target_map ||= begin
        tmap = {}
        @releases.each do |release|
          release.targets.each do |target|
            tmap[target] = release
          end
        end
        tmap
      end
    end

    def milestone_boundaries
      @milestone_boundaries ||= begin
        boundaries = { :earliest => Date.today, :latest => (Date.today - 1800) }
        @releases.each do |release|
          next unless release.uses_milestones?
          ms = release.milestones
          [ms.start,ms.feature_complete,ms.code_freeze,ms.ga].each do |m|
            next if m.date.nil?
            if m.date < boundaries[:earliest]
              boundaries[:earliest] = m.date
            end
            if m.date > boundaries[:latest]
              boundaries[:latest] = m.date
            end
          end
        end
        boundaries
      end
    end
  end
end
