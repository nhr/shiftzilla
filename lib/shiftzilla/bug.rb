module Shiftzilla
  class Bug
    attr_reader :id, :first_seen, :last_seen, :test_blocker, :ops_blocker, :owner, :component, :pm_score, :cust_cases, :tgt_release, :summary

    def initialize(bzid,binfo)
      @id           = bzid
      @first_seen   = binfo[:snapdate]
      @last_seen    = binfo[:snapdate]
      @test_blocker = binfo[:test_blocker]
      @ops_blocker  = binfo[:ops_blocker]
      @owner        = binfo[:owner]
      @summary      = binfo[:summary]
      @component    = binfo[:component]
      @pm_score     = binfo[:pm_score]
      @cust_cases   = binfo[:cust_cases]
      @tgt_release  = binfo[:tgt_release]
    end

    def update(binfo)
      @last_seen    = binfo[:snapdate]
      @test_blocker = binfo[:test_blocker]
      @ops_blocker  = binfo[:ops_blocker]
      @owner        = binfo[:owner]
      @summary      = binfo[:summary]
      @component    = binfo[:component]
      @pm_score     = binfo[:pm_score]
      @cust_cases   = binfo[:cust_cases]
      @tgt_release  = binfo[:tgt_release]
    end

    def short_summary
      @summary[0..30].gsub(/\s\w+\s*$/, '...')
    end

    def age
      (@last_seen - @first_seen).to_i
    end

    def semver
      parts = @tgt_release.split('.')
      if parts.length == 1
        return @tgt_release
      end
      semver = ''
      first_part = true
      parts.each do |part|
        unless is_number?(part)
          semver += part
        else
          semver += ("%09d" % part).to_s
        end
        # A version like '3.z' gets a middle 0 for sort purposes.
        if first_part and parts.length == 2
          semver += ("%09d" % 0).to_s
        end
        first_part = false
      end
      return semver
    end

    private

    def is_number?(val)
      val.to_f.to_s == val.to_s || val.to_i.to_s == val.to_s
    end
  end
end