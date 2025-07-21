## MySQL Config Suggester (Ruby)
An interactive Ruby script designed to assist in optimizing MySQL (my.cnf) configurations based on server characteristics and database usage patterns. This script gathers system information (RAM, CPU, disk type) and asks a few questions about your MySQL workload to generate tailored suggestions.

## Features
Automatic Hardware Detection: Identifies total RAM, number of CPU cores, and attempts to determine disk type (SSD/HDD).

Interactive Prompts: Asks about your predominant workload (read-heavy, write-heavy, mixed), expected concurrent connections, and whether you primarily use InnoDB tables.

Customized Suggestions: Generates a my.cnf file with optimized settings for key parameters such as innodb_buffer_pool_size, max_connections, innodb_flush_method (for SSDs), and others.

my.cnf Location: Attempts to locate your existing my.cnf file to facilitate comparison.

Automatic Backup: Creates a backup of your original my.cnf file before suggesting any modifications.

Diff Generation: Displays the differences between your current my.cnf and the suggested configurations, making it easy to review changes.

New File Option: Offers the option to generate a new file (my_new.cnf) with the recommended configurations for manual review before application.

## Prerequisites
To run this script, you will need:

Ruby: Version 2.x or higher.

Git: For cloning the repository (optional, if you download manually).

diff-lcs Gem: Used for generating the configuration comparison (diff).

Gem Installation
Bash

gem install diff-lcs
How to Use
Clone the Repository (or Download):

Bash

git clone https://github.com/YOUR_USERNAME/mysql-config-suggester-ruby.git
cd mysql-config-suggester-ruby
(Replace YOUR_USERNAME with your GitHub username)

Execute the Script:

Bash

ruby main_mysql_script.rb
Answer the Questions:
The script will ask several questions about your server environment and MySQL usage. Provide accurate answers to help the script generate the most suitable recommendations.

Review the Suggestions:
The script will display the suggested differences (diff) for your my.cnf and ask if you wish to create a new my_new.cnf file with the recommendations.

## ATTENTION:

ALWAYS carefully review the suggested configurations before applying them to a production environment.

This script provides a starting point for optimization. Fine-tuning may require continuous monitoring and further refinement.

Restart MySQL:
For the new configurations to take effect, you must restart the MySQL service.

## Examples:

Ubuntu/Debian: sudo systemctl restart mysql

CentOS/RHEL: sudo systemctl restart mysqld

Other systems: Consult the specific documentation for your distribution or MySQL installation.

## Project Structure
├── main_mysql_script.rb      # Main script: orchestrates data collection and configuration generation.
└── lib_mysql/                # Auxiliary modules containing specific logic.
    ├── system_info_mysql.rb  # Gathers system information (RAM, CPU, Disk Type).
    └── mysql_config.rb       # Contains the logic for generating my.cnf recommendations and finding the existing config file.
Contributions
Contributions are welcome! If you have suggestions, improvements, or find any bugs, feel free to open an issue or submit a Pull Request.

## License
This project is licensed under the MIT - see the LICENSE file for more details.
