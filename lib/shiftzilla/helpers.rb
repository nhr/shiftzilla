require 'date'
require 'fileutils'
require 'haml'
require 'fileutils'
require 'sqlite3'
require 'tmpdir'
require 'yaml'

module Shiftzilla
  module Helpers
    BZ_URL     = 'https://bugzilla.redhat.com/show_bug.cgi?id='
    SZA_DIR    = File.join(ENV['HOME'],'.shiftzilla')
    ARCH_DIR   = File.join(SZA_DIR,'archive')
    CFG_FILE   = File.join(SZA_DIR,'shiftzilla_cfg.yml')
    DB_FNAME   = 'shiftzilla.sqlite'
    DB_FPATH   = File.join(SZA_DIR,DB_FNAME)
    THIS_PATH  = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
    HAML_TMPL  = File.expand_path(File.join(File.dirname(THIS_PATH), '../../template.haml'))
    CFG_TMPL   = File.expand_path(File.join(File.dirname(THIS_PATH), '../../shiftzilla_cfg.yml.tmpl'))
    SQL_TMPL   = File.expand_path(File.join(File.dirname(THIS_PATH), '../../shiftzilla.sql.tmpl'))
    VENDOR_DIR = File.expand_path(File.join(File.dirname(THIS_PATH), '../../vendor'))

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

    def timestamp
      DateTime.now.to_s
    end

    def bug_url(bug_id)
      return "#{BZ_URL}#{bug_id}"
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

    def all_bugs_query(snapshot)
      return "SELECT AB.'Bug ID', AB.'Component', AB.'Target Release', AB.'Assignee', AB.'Status', AB.'Summary', AB.'Keywords', AB.'PM Score', AB.'External Bugs' FROM ALL_BUGS AB WHERE AB.'Snapshot' = date('#{snapshot}')"
    end

    def component_bugs_query(components,snapshot)
      rclause = list_clause(components)
      rfilter = rclause == '' ? '' : " AND AB.'Component' #{rclause}"
      return "SELECT AB.'Bug ID', AB.'Component', AB.'Target Release', AB.'Assignee', AB.'Status', AB.'Summary', AB.'Keywords', AB.'PM Score', AB.'External Bugs' FROM ALL_BUGS AB WHERE AB.'Snapshot' = date('#{snapshot}')#{rfilter} ORDER BY AB.'Target Release' DESC"
    end

    def component_bugs_count(components,snapshot)
      rclause = list_clause(components)
      rfilter = rclause == '' ? '' : " AND AB.'Component' #{rclause}"
      return "SELECT count(*) FROM ALL_BUGS AB WHERE AB.'Snapshot' = date('#{snapshot}')#{rfilter}"
    end

    def all_snapshots
      @all_snapshots ||= begin
        all_snapshots = []
        dbh.execute('SELECT DISTINCT Snapshot FROM ALL_BUGS ORDER BY Snapshot ASC') do |row|
          all_snapshots << row[0]
        end
        all_snapshots
      end
    end

    def latest_snapshot
      all_snapshots[-1]
    end

    def field_map
      {
        :assigned_to      => 'Assignee',
        :component        => 'Component',
        :id               => 'Bug ID',
        :keywords         => 'Keywords',
        :cf_pm_score      => 'PM Score',
        :status           => 'Status',
        :summary          => 'Summary',
        :target_release   => 'Target Release',
        :external_bugs    => 'External Bugs',
      }
    end

    private

    def list_clause(list)
      return '' if list.length == 0
      if list.length > 1
        stmt = list.map{ |t| "'#{t}'" }.join(',')
        return "IN (#{stmt})"
      end
      return "== '#{list[0]}'"
    end

    def db_backed_up
      @db_backed_up ||= false
    end
  end
end
