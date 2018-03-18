module Shiftzilla
  class SnapData
    attr_reader :id
    attr_accessor :bug_ids, :tb_ids, :cc_ids, :new_bugs, :closed_bugs, :new_tb, :closed_tb, :new_cc, :closed_cc

    def initialize(snapshot)
      @id          = snapshot
      @bug_ids     = []
      @tb_ids      = []
      @cc_ids      = []
      @new_bugs    = 0
      @closed_bugs = 0
      @new_tb      = 0
      @closed_tb   = 0
      @new_cc      = 0
      @closed_cc   = 0
    end

    def total_bugs
      @bug_ids.length
    end

    def total_tb
      @tb_ids.length
    end

    def total_cc
      @cc_ids.length
    end
  end
end