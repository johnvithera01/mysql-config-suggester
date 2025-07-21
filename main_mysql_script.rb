require_relative 'lib_mysql/system_info_mysql'
require_relative 'lib_mysql/mysql_config'
require 'fileutils' # Para operações de arquivo

class MySQLEnvironmentAnalyzer
  def run
    puts "Iniciando a análise e sugestão de configuração para MySQL..."

    # 1. Obter informações do sistema
    disk_type = SystemInfoMySQL.get_disk_type
    puts "Tipo de disco detectado: #{disk_type}"

    ram_info = SystemInfoMySQL.get_ram_info
    swap_info = SystemInfoMySQL.get_swap_info
    if ram_info[:total_mb] == 0 || ram_info[:total] == "Erro"
      puts "Erro ao obter informações de RAM. Abortando a configuração."
      return
    end
    puts "Memória RAM: #{ram_info[:total]} (Total), #{ram_info[:free]} (Disponível), #{ram_info[:total_mb].round(2)} MB (Total para cálculos)"
    puts "Swap: #{swap_info[:total]} (Total), #{swap_info[:free]} (Disponível)"

    cpu_cores = SystemInfoMySQL.get_cpu_cores
    if cpu_cores.to_s.start_with?("Erro") || cpu_cores == 0
      puts "Erro ao obter número de núcleos da CPU. Abortando a configuração."
      return
    end
    puts "Número de núcleos da CPU: #{cpu_cores}"

    # 2. Perguntar sobre o uso do MySQL
    puts "\n--- Informações sobre o uso do MySQL ---"
    workload = ""
    until ["leitura", "escrita", "misto"].include?(workload)
      print "Tipo de workload predominante (leitura, escrita, misto): "
      workload = STDIN.gets.chomp.downcase
      unless ["leitura", "escrita", "misto"].include?(workload)
        puts "Por favor, digite 'leitura', 'escrita' ou 'misto'."
      end
    end

    connections = 0
    while connections <= 0
      print "Número de conexões simultâneas esperadas (ex: 100, 500): "
      connections = STDIN.gets.chomp.to_i
      unless connections > 0
        puts "Por favor, insira um número válido de conexões (maior que 0)."
      end
    end

    innodb_only_input = ""
    until ["s", "n"].include?(innodb_only_input)
      print "Você usa principalmente tabelas InnoDB? (s/n): "
      innodb_only_input = STDIN.gets.chomp.downcase
      unless ["s", "n"].include?(innodb_only_input)
        puts "Por favor, digite 's' para sim ou 'n' para não."
      end
    end
    innodb_only = (innodb_only_input == "s")

    # 3. Gerar e aplicar alterações no my.cnf
    puts "\n--- Geração do my.cnf recomendado ---"
    recommended_config_content = MySQLConfig.generate_recommendations(
      disk_type: disk_type,
      ram_total_mb: ram_info[:total_mb],
      cpu_cores: cpu_cores,
      workload: workload,
      connections: connections,
      innodb_only: innodb_only
    )

    # Localizar o my.cnf atual
    my_cnf_path = MySQLConfig.find_my_cnf_path
    if my_cnf_path.nil?
      puts "Atenção: Não foi possível localizar o my.cnf automaticamente."
      puts "As recomendações foram impressas. Por favor, aplique-as manualmente no seu arquivo de configuração."
      # Salva o arquivo recomendado em um local temporário mesmo assim
      output_filename = "my_recommended_#{Time.now.strftime('%Y%m%d_%H%M%S')}.cnf"
      File.write(output_filename, recommended_config_content)
      puts "Um arquivo com as recomendações foi salvo como '#{output_filename}'."
    else
      puts "Arquivo my.cnf encontrado em: #{my_cnf_path}"
      backup_path = "#{my_cnf_path}.bak_#{Time.now.strftime('%Y%m%d_%H%M%S')}"

      # Criar backup
      begin
        FileUtils.cp(my_cnf_path, backup_path)
        puts "Backup do arquivo original criado em: #{backup_path}"
      rescue => e
        puts "Erro ao criar backup do arquivo original: #{e.message}"
        puts "Recomendações impressas. Abortando a modificação automática do arquivo."
        # Salva o arquivo recomendado em um local temporário mesmo assim
        output_filename = "my_recommended_#{Time.now.strftime('%Y%m%d_%H%M%S')}.cnf"
        File.write(output_filename, recommended_config_content)
        puts "Um arquivo com as recomendações foi salvo como '#{output_filename}'."
        return
      end

      # Gerar diff
      diff = MySQLConfig.generate_diff(my_cnf_path, recommended_config_content)
      if diff.empty?
        puts "Nenhuma diferença significativa entre o arquivo atual e as recomendações."
      else
        puts "\n--- Diferenças sugeridas para my.cnf (diff) ---"
        puts diff
        puts "--- Fim do Diff ---"

        puts "\n❓ Deseja criar um novo arquivo 'my_new.cnf' com as recomendações? (s/n)"
        answer = STDIN.gets.chomp.downcase
        if answer == 's'
          new_config_path = File.join(File.dirname(my_cnf_path), "my_new.cnf")
          File.write(new_config_path, recommended_config_content)
          puts "Novo arquivo de configuração gerado em: #{new_config_path}"
          puts "Por favor, revise '#{new_config_path}' e, se estiver satisfeito, considere substituir o '#{my_cnf_path}' original por ele."
          puts "Lembre-se de **reiniciar o serviço do MySQL** para que as novas configurações entrem em vigor."
        else
          puts "Nenhuma alteração feita no arquivo. As recomendações foram apenas impressas acima."
        end
      end
    end

    puts "\nAnálise do ambiente MySQL concluída."
    puts "Para que as novas configurações entrem em vigor, você deve **reiniciar o serviço do MySQL**."
    puts "Exemplo (Ubuntu): sudo systemctl restart mysql"
    puts "Exemplo (CentOS/RHEL): sudo systemctl restart mysqld"
  end
end

MySQLEnvironmentAnalyzer.new.run