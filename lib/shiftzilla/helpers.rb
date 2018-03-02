require 'fileutils'
require 'gruff'
require 'haml'
require 'fileutils'
require 'sqlite3'
require 'tmpdir'
require 'yaml'

module Shiftzilla
  module Helpers
    BZ_URL    = 'https://bugzilla.redhat.com/show_bug.cgi?id='
    SZA_DIR   = File.join(ENV['HOME'],'.shiftzilla')
    ARCH_DIR  = File.join(SZA_DIR,'archive')
    CFG_FILE  = File.join(SZA_DIR,'shiftzilla_cfg.yml')
    DB_FNAME  = 'shiftzilla.sqlite'
    DB_FPATH  = File.join(SZA_DIR,DB_FNAME)
    THIS_PATH = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
    HAML_TMPL = File.expand_path(File.join(File.dirname(THIS_PATH), '../../template.haml'))
    CFG_TMPL  = File.expand_path(File.join(File.dirname(THIS_PATH), '../../shiftzilla_cfg.yml.tmpl'))
    SQL_TMPL  = File.expand_path(File.join(File.dirname(THIS_PATH), '../../shiftzilla.sql.tmpl'))

    GRAPH_DIMENSIONS = '800x400'
    GRAPH_THEME      = {
      :colors => [
        '#268bd2', # Blue
        '#cb4b16', # Orange
        '#859900', # Green
        '#2aa198', # Cyan
        '#d33682', # Magenta
        '#6c71c4', # Violet
        '#b58900', # Yellow
        '#dc322f', # Red
      ],
      :marker_color      => '#93a1a1', # Base1
      :font_color        => '#586e75', # Base01
      :background_colors => '#fdf6e3', # Base3
      :background_image  => nil,
    }

    def tmp_dir
      @tmp_dir ||= Dir.mktmpdir('shiftzilla-reports-')
    end

    def cfg_file
      @cfg_file ||= YAML.load_file(CFG_FILE)
    end

    def dbh
      @dbh ||= SQLite3::Database.new(DB_FPATH)
    end

    def haml_engine
      @haml_engine ||= Haml::Engine.new(File.read(HAML_TMPL))
    end

    def pick_max(series_list)
      max_val = 0
      series_list.each do |s|
        smax = s.select{ |v| not v.nil? }.max
        next if smax.nil?
        next unless smax > max_val
        max_val = smax
      end
      return max_val
    end

    def new_graph(labels,max_y)
      g = Gruff::Line.new(GRAPH_DIMENSIONS)
      g.theme            = GRAPH_THEME
      g.line_width       = 2
      g.labels           = labels
      g.y_axis_increment = set_axis_increment(max_y)
      g.hide_dots        = true
      return g
    end

    def backup_db
      unless db_backed_up
        today = Date.today.strftime('%Y-%m-%d')
        tpath = File.join(ARCH_DIR,today)
        puts "TP: #{tpath}"
        unless Dir.exists?(tpath)
          Dir.mkdir(tpath)
        end
        apath    = ''
        copy_idx = 0
        loop do
          copynum = "%02d" % copy_idx
          apath   = File.join(tpath,"#{copynum}-#{DB_FNAME}")
          break unless File.exists?(apath)
          copy_idx += 1
        end
        FileUtils.cp DB_FPATH, apath
        puts "Backed up the database."
        @db_backed_up = true
      end
    end

    def bug_url(bug_id)
      return "#{BZ_URL}#{bug_id}"
    end

    # Hat tip to https://stackoverflow.com/a/24753003 for this:
    def business_days_between(start_date, end_date)
      days_between = (end_date - start_date).to_i
      return 0 unless days_between > 0
      whole_weeks, extra_days = days_between.divmod(7)
      unless extra_days.zero?
        extra_days -= if start_date.tomorrow.wday <= end_date.wday
                        [start_date.tomorrow.sunday?, end_date.saturday?].count(true)
                      else
                        2
                      end
      end
      (whole_weeks * 5) + extra_days
    end

    def set_axis_increment(initial_value)
      case
      when initial_value < 10
        return 1
      when initial_value < 20
        return 2
      when initial_value < 50
        return 5
      when initial_value < 100
        return 10
      when initial_value < 200
        return 20
      when initial_value < 400
        return 25
      else
        return 100
      end
    end

    def summary_queries
      [:count_release_bugs_today,
       :count_no_tgt_rel_today,
       :count_new_today,
       :count_closed_yesterday,
       :count_test_blockers_today,
       :list_blockers_closed,
       :list_blockers_opened,
      ]
    end

    def release_clause(releases)
      return '' if releases.nil? or releases.length == 0
      if releases.length > 1
        release_list   = releases.map{ |r| "'#{r}'" }.join(',')
        return "IN (#{release_list})"
      end
      return "== '#{releases[0]}''"
    end

    def queries(id,snapshot = nil,releases = nil)
      tgt_rel_clause = release_clause(releases)
      if not releases.nil? and releases.length > 0
        if releases.length > 1
          release_list   = releases.map{ |r| "'#{r}'" }.join(',')
          release_clause = " AND TB.'Target Release' IN (#{release_list})"
        else
          release_clause = " AND TB.'Target Release' = '#{releases[0]}''"
        end
      end
      qmap = {
        :count_release_bugs_today  => {
          :label => 'Release bugs today',
          :query => 'SELECT count(*) FROM RELEASE_BUGS_TODAY',
        },
        :count_no_tgt_rel_today    => {
          :label => 'No target release',
          :query => 'SELECT count(*) FROM RELEASE_BUGS_NO_TARGET_RELEASE_TODAY',
        },
        :count_new_today           => {
          :label => 'New',
          :query => 'SELECT count(*) FROM RELEASE_BUGS_NEW_TODAY',
        },
        :count_closed_yesterday    => {
          :label => 'Closed',
          :query => 'SELECT count(*) FROM RELEASE_BUGS_CLOSED_YESTERDAY',
        },
        :count_test_blockers_today => {
          :label => 'Test blockers today',
          :query => 'SELECT count(*) FROM TEST_BLOCKERS_TODAY',
        },
        :list_blockers_closed      => {
          :label => 'Blockers closed',
          :query => "SELECT TBCY.'Bug ID',TBCY.'Component',TBCY.'Assignee',TBCY.'Summary' FROM TEST_BLOCKERS_CLOSED_YESTERDAY TBCY",
        },
        :list_blockers_opened      => {
          :label => 'Blockers opened',
          :query => "SELECT TBNT.'Bug ID',TBNT.'Component',TBNT.'Assignee',TBNT.'Summary' FROM TEST_BLOCKERS_NEW_TODAY TBNT",
        },
        :dyn_no_tgt_release_by_snap => {
          :label => 'No target release by snapshot',
          :query => "SELECT RB.'Bug ID', RB.'Component', RB.'Assignee', RB.'Summary' FROM RELEASE_BUGS RB WHERE RB.'Target Release' LIKE '%---%' AND RB.'Snapshot' = date('#{snapshot}')",
        },
        :dyn_report_release_bugs => {
          :label => 'All release bugs by snapshot',
          :query => "SELECT RB.'Bug ID', RB.'Component', RB.'Target Release', RB.'Assignee', RB.'Summary', RB.'PM Score', RB.'External Bugs' FROM RELEASE_BUGS RB WHERE RB.'Snapshot' = date('#{snapshot}')",
        },
        :dyn_report_test_blockers => {
          :label => 'All test blockers for the specified release(s) by snapshot',
          :query => "SELECT TB.'Bug ID', TB.'Component', TB.'Assignee', TB.'Summary' FROM TEST_BLOCKERS TB WHERE TB.'Snapshot' = date('#{snapshot}') AND TB.'Target Release' #{tgt_rel_clause}",
        }
      }
      return qmap[id]
    end

    def snapshots
      @snapshots ||= begin
        snapshots = []
        dbh.execute('SELECT DISTINCT Snapshot FROM RELEASE_BUGS ORDER BY Snapshot ASC') do |row|
          snapshots << row[0]
        end
        snapshots
      end
    end

    def first_snapshot
      @first_snapshot ||= snapshots[0]
    end

    def first_snap_date
      @first_snap_date ||= Date.parse(first_snapshot)
    end

    def latest_snapshot
      @latest_snapshot ||= snapshots[-1]
    end

    def latest_snap_date
      @latest_snap_date ||= Date.parse(latest_snapshot)
    end

    def field_map
      {
        :assigned_to      => 'Assignee',
        :component        => 'Component',
        :id               => 'Bug ID',
        :keywords         => 'Keywords',
        :last_change_time => 'Changed',
        :cf_pm_score      => 'PM Score',
        :priority         => 'Priority',
        :product          => 'Product',
        :qa_contact       => 'QA Contact',
        :reporter         => 'Reporter',
        :resolution       => 'Resolution',
        :severity         => 'Severity',
        :status           => 'Status',
        :summary          => 'Summary',
        :target_release   => 'Target Release',
        :version          => 'Version',
        :external_bugs    => 'External Bugs',
      }
    end

    private

    def db_backed_up
      @db_backed_up ||= false
    end
  end
end
