require 'shiftzilla/group'
require 'shiftzilla/helpers'
require 'shiftzilla/milestones'
require 'shiftzilla/source'
require 'shiftzilla/team'

module Shiftzilla
  class Config
    attr_reader :teams, :groups, :sources, :milestones, :releases, :ssh

    def initialize
      @teams    = []
      @groups   = []
      @sources  = []
      @releases = []
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
      @milestones = Shiftzilla::Milestones.new(cfg_file['Milestones'])
      cfg_file['Releases'].each do |release|
        @releases << release
      end
      @ssh = {
        :host => cfg_file['SSH']['host'],
        :path => cfg_file['SSH']['path'],
        :url  => cfg_file['SSH']['url'],
      }
    end
  end
end
