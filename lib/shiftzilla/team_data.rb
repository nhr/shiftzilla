module Shiftzilla
  class TeamData
    attr_accessor :team, :team_title, :team_file, :file_prefix, :snaps, :bugs, :bug_avg_age, :tb_avg_age, :prev_snap, :last_seen, :series

    def initialize(team = nil)
      @team        = team
      @team_title  = ''
      @team_file   = ''
      @file_prefix = ''
      @snaps       = {}
      @bugs        = {}
      @bug_avg_age = 0
      @tb_avg_age  = 0
      @prev_snap   = nil
      @last_seen   = nil
      @series      = {
        :ideal      => [],
        :total      => [],
        :no_tgt_rel => [],
        :new        => [],
        :closed     => [],
        :tb_total   => [],
        :tb_new     => [],
        :tb_closed  => [],
      }
    end
  end
end
