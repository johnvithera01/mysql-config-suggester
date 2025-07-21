# lib_mysql/mysql_config.rb
require 'open3' # Para rodar comandos e pegar saída/erro
require 'diff/lcs' # Para gerar o diff

module MySQLConfig
  # Tenta encontrar o caminho do my.cnf
  def self.find_my_cnf_path
    possible_paths = [
      '/etc/my.cnf',
      '/etc/mysql/my.cnf',
      '/usr/local/mysql/my.cnf',
      '~/.my.cnf',
      '/var/lib/mysql/my.cnf' # Em alguns casos
    ]

    possible_paths.each do |path|
      expanded_path = File.expand_path(path)
      return expanded_path if File.exist?(expanded_path) && File.readable?(expanded_path)
    end

    # Tenta encontrar via "mysql --help --verbose | grep "Default options""
    stdout, stderr, status = Open3.capture3('mysql --help --verbose')
    if status.success?
      stdout.each_line do |line|
        if line =~ /Default options are read from the following files in the given order:/
          
          next_line = stdout.each_line.to_a[stdout.each_line.to_a.index(line) + 1]
          if next_line
            
            paths_in_help = next_line.scan(/\S+\.cnf/)
            paths_in_help.each do |path|
              return path if File.exist?(path) && File.readable?(path)
            end
          end
        end
      end
    end

    nil # Não encontrado
  end

  def self.generate_recommendations(disk_type:, ram_total_mb:, cpu_cores:, workload:, connections:, innodb_only:)
    suggestions = []

    # Seção [mysqld]
    suggestions << "[mysqld]"
    suggestions << "# Arquivo de log de erros (altamente recomendado)"
    suggestions << "log_error = /var/log/mysql/error.log"
    suggestions << "# PID file"
    suggestions << "pid_file = /var/run/mysqld/mysqld.pid"
    suggestions << "# Data directory"
    suggestions << "datadir = /var/lib/mysql"
    suggestions << ""

    # Conexões
    suggestions << "# --- Conexões ---"
    # min 150, max 2000-4000 (depende da RAM e workload)
    actual_max_connections = [connections * 1.2, 150].max.to_i # 20% a mais para folga
    suggestions << "max_connections = #{actual_max_connections} # Conexões esperadas + 20% de folga"
    suggestions << "max_user_connections = 0 # 0 significa sem limite por usuário"
    suggestions << "wait_timeout = 28800 # Tempo limite para conexão inativa (em segundos)"
    suggestions << "interactive_timeout = 28800"
    suggestions << ""

    # Buffer Pool do InnoDB (principal parâmetro de desempenho)
    suggestions << "# --- InnoDB Settings ---"
    # Geralmente 50-70% da RAM dedicada ao MySQL para InnoDB
    # Vamos usar 60% como ponto de partida
    innodb_buffer_pool_size_mb = (ram_total_mb * 0.6).to_i
    innodb_buffer_pool_size_mb = [innodb_buffer_pool_size_mb, 256].max # Mínimo 256MB
    suggestions << "innodb_buffer_pool_size = #{innodb_buffer_pool_size_mb}M"
    suggestions << "innodb_buffer_pool_instances = #{[cpu_cores / 2, 1].max}" # 1-8 instâncias para cores > 8GB buffer pool
    if innodb_buffer_pool_size_mb < 1024 # Para buffer pools menores, 1 instância é suficiente
      suggestions << "# innodb_buffer_pool_instances = 1 # Para buffer pools menores"
    end
    suggestions << "innodb_log_file_size = #{[innodb_buffer_pool_size_mb / 8, 256].min.to_i}M # 1/8 a 1/4 do buffer pool size, limite comum 512M para versões antigas"
    suggestions << "innodb_log_files_in_group = 2"
    suggestions << "innodb_flush_log_at_trx_commit = 1 # 1 para máxima durabilidade (menos desempenho), 0 ou 2 para melhor desempenho (risco de perda de 1s de dados)"
    suggestions << "innodb_file_per_table = 1 # Cada tabela InnoDB em seu próprio arquivo .ibd (altamente recomendado)"
    suggestions << "innodb_io_capacity = #{disk_type == 'SSD' ? 1000 : 200} # Ajustar conforme IOPS do disco"
    suggestions << "innodb_read_io_threads = #{cpu_cores * 2}"
    suggestions << "innodb_write_io_threads = #{cpu_cores * 2}"
    suggestions << ""

    # Otimizações de disco para InnoDB
    if disk_type == 'SSD'
      suggestions << "# Otimizações para SSD"
      suggestions << "innodb_flush_method = O_DIRECT # Melhora o I/O em SSDs"
      suggestions << ""
    end

    # Key Buffer (para MyISAM)
    if innodb_only
      suggestions << "# Para ambientes que usam APENAS InnoDB, o key_buffer_size pode ser pequeno."
      suggestions << "key_buffer_size = 8M"
    else
      # Se usar MyISAM, dar um pouco mais, mas ainda priorizar InnoDB
      key_buffer_size_mb = [ram_total_mb * 0.05, 64].min.to_i # Max 5% da RAM ou 64MB
      suggestions << "key_buffer_size = #{key_buffer_size_mb}M # Ajustar se houver muitas tabelas MyISAM"
    end
    suggestions << ""

    # Cache de threads
    suggestions << "# --- Thread Cache ---"
    # Um bom número para thread_cache_size é 10% de max_connections, com um mínimo.
    thread_cache_size = (connections / 10).to_i
    thread_cache_size = [thread_cache_size, 16].max
    thread_cache_size = [thread_cache_size, 128].min # Limite prático
    suggestions << "thread_cache_size = #{thread_cache_size} # Melhora desempenho para muitas conexões"
    suggestions << ""

    # Tamanho de tabelas temporárias
    suggestions << "# --- Temp Table Sizes ---"
    tmp_table_size_mb = [ram_total_mb * 0.05, 64].min.to_i # 5% da RAM ou 64MB
    suggestions << "tmp_table_size = #{tmp_table_size_mb}M"
    suggestions << "max_heap_table_size = #{tmp_table_size_mb}M"
    suggestions << ""

    # Cache de consultas (query_cache) - Geralmente desativado em versões modernas do MySQL 5.6+
    # Devido a problemas de concorrência.
    suggestions << "# --- Query Cache (Review carefully!) ---"
    suggestions << "# query_cache_size = 0"
    suggestions << "# query_cache_type = 0 # Desativar o Query Cache é recomendado para a maioria dos workloads modernos"
    suggestions << ""

    # Tamanhos de buffer para leitura/escrita
    suggestions << "# --- Read/Write Buffers ---"
    case workload
    when "leitura"
      suggestions << "# Otimizações para workload de Leitura"
      suggestions << "read_buffer_size = 2M"
      suggestions << "read_rnd_buffer_size = 4M"
    when "escrita"
      suggestions << "# Otimizações para workload de Escrita"
      suggestions << "read_buffer_size = 256K" # Pode ser menor
      suggestions << "read_rnd_buffer_size = 512K"
    when "misto"
      suggestions << "# Configurações para workload Misto"
      suggestions << "read_buffer_size = 1M"
      suggestions << "read_rnd_buffer_size = 2M"
    end
    suggestions << ""

    # Packet size
    suggestions << "# --- Other Common Settings ---"
    suggestions << "max_allowed_packet = 64M # Aumentar se houver transferências de dados grandes (BLOBs)"
    suggestions << "skip-name-resolve # Evita consultas DNS para conexões, acelera o login"
    suggestions << ""

    # Seção [client] e [mysql]
    suggestions << "[client]"
    suggestions << "port = 3306"
    suggestions << "socket = /var/run/mysqld/mysqld.sock" # Caminho comum, pode variar

    suggestions << "[mysql]"
    suggestions << "prompt = '\\u@\\h:\\d \\R:\\m:\\s> '" # Um prompt útil para o cliente MySQL
    suggestions << ""

    suggestions.join("\n")
  end

  def self.generate_diff(current_config_path, recommended_content)
    current_content = File.read(current_config_path)
    current_lines = current_content.lines.map(&:chomp)
    recommended_lines = recommended_content.lines.map(&:chomp)

    diff = Diff::LCS.diff(current_lines, recommended_lines)

    diff_output = []
    diff.each do |hunk|
      hunk.each do |change|
        case change.action
        when '-' # Removido da configuração atual
          diff_output << "- #{change.element}"
        when '+' # Adicionado na recomendação
          diff_output << "+ #{change.element}"
        when '!' # Modificado
          # Need to find the corresponding change to show "before -> after"
          # This simple diff doesn't show context easily for '!', so we'll show both lines.
          # A more sophisticated diff library might be needed for a precise "before/after" for '!'
          # For simplicity, if we see '!', we'll consider it a removal and an addition for now.
          # The Diff::LCS provides 'change.old_element' and 'change.new_element' for '!'
          # but iterating `diff` as we do doesn't pair them perfectly by default.
          # A proper diff tool shows context for '!', e.g., '--- old_value' and '+++ new_value'.
          # For now, let's treat modified as deleted + added from the perspective of simple line comparison.
          # Actually, Diff::LCS provides an 'original_line' and 'new_line' that we can use.
          # Let's adjust for this specific type of change.
          # We'll rely on the default behavior of Diff::LCS to show deleted (-) and added (+).
          # If a line is truly modified, it will appear as a '-' then a '+' in the diff.
          # For example, if 'key_buffer_size = 16M' becomes 'key_buffer_size = 32M',
          # the diff will show '- key_buffer_size = 16M' and '+ key_buffer_size = 32M'.
          # This is standard behavior for line-based diffs.
        end
      end
    end
    diff_output.join("\n")
  end
end