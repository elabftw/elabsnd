#!/bin/bash
# install mysql php nginx and elabftw

GIT_REPO="https://github.com/elabftw/elabftw"
GIT_BRANCH="sandstorm"

# When you change this file, you must take manual action. Read this doc:
# - https://docs.sandstorm.io/en/latest/vagrant-spk/customizing/#setupsh

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# add mysql 5.7 repo
echo -e "deb http://repo.mysql.com/apt/debian/ stretch mysql-5.7\ndeb-src http://repo.mysql.com/apt/debian/ stretch mysql-5.7" > /etc/apt/sources.list.d/mysql.list
wget -O /tmp/RPM-GPG-KEY-mysql https://repo.mysql.com/RPM-GPG-KEY-mysql
apt-key add /tmp/RPM-GPG-KEY-mysql

# add php 7.1 repo
apt-get -y install apt-transport-https lsb-release ca-certificates
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

# add nodejs repo
curl -sL https://deb.nodesource.com/setup_8.x | bash -

# add yarn repo
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list

# install nginx git mysql and php
apt-get update
apt-get install -y nginx git mysql-server \
    php7.1-cli \
    php7.1-curl \
    php7.1-dom \
    php7.1-fpm \
    php7.1-gd \
    php7.1-gettext \
    php7.1-mbstring \
    php7.1-mcrypt \
    php7.1-mysql \
    php7.1-zip \
    yarn
service nginx stop
service php7.1-fpm stop
service mysql stop
systemctl disable nginx
systemctl disable php7.1-fpm
systemctl disable mysql
# patch /etc/php/7.0/fpm/pool.d/www.conf to not change uid/gid to www-data
sed --in-place='' \
        --expression='s/^listen.owner = www-data/;listen.owner = www-data/' \
        --expression='s/^listen.group = www-data/;listen.group = www-data/' \
        --expression='s/^user = www-data/;user = www-data/' \
        --expression='s/^group = www-data/;group = www-data/' \
        /etc/php/7.1/fpm/pool.d/www.conf
# patch /etc/php/7.0/fpm/php-fpm.conf to not have a pidfile
sed --in-place='' \
        --expression='s/^pid =/;pid =/' \
        /etc/php/7.1/fpm/php-fpm.conf
# patch /etc/php/7.0/fpm/php-fpm.conf to place the sock file in /var 
sed --in-place='' \
       --expression='s/^listen = \/run\/php\/php7.1-fpm.sock/listen = \/var\/run\/php\/php7.1-fpm.sock/' \
        /etc/php/7.1/fpm/pool.d/www.conf
# patch /etc/php/7.0/fpm/pool.d/www.conf to no clear environment variables
# so we can pass in SANDSTORM=1 to apps
sed --in-place='' \
        --expression='s/^;clear_env = no/clear_env=no/' \
        /etc/php/7.1/fpm/pool.d/www.conf
# patch mysql conf to not change uid, and to use /var/tmp over /tmp
# for secure-file-priv see https://github.com/sandstorm-io/vagrant-spk/issues/195
sed --in-place='' \
        --expression='s/^user\t\t= mysql/#user\t\t= mysql/' \
        --expression='s,^tmpdir\t\t= /tmp,tmpdir\t\t= /var/tmp,' \
        --expression='/\[mysqld]/ a\ secure-file-priv = ""\' \
        /etc/mysql/my.cnf
# patch mysql conf to use smaller transaction logs to save disk space
cat <<EOF > /etc/mysql/conf.d/sandstorm.cnf
[mysqld]
# Set the transaction log file to the minimum allowed size to save disk space.
innodb_log_file_size = 1048576
# Set the main data file to grow by 1MB at a time, rather than 8MB at a time.
innodb_autoextend_increment = 1
EOF


if [ ! -f /opt/elabftw/composer.json ] ; then
    git clone -b "$GIT_BRANCH" --depth 1 "$GIT_REPO" /opt/elabftw
    cd /opt/elabftw
    if [ ! -f composer.phar ] ; then
        curl -sS https://getcomposer.org/installer | php
    fi
    php composer.phar install --no-dev --no-interaction -a
    yarn install
    yarn run buildall
    cat <<EOF > /opt/elabftw/config.php
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', 'elabftw');
define('DB_USER', 'root');
define('DB_PASSWORD', '');
define('ELAB_ROOT', '/opt/elabftw/');
define('SECRET_KEY', 'def00000d7cf7927bb2675d62bf694cfa44488f6b078ef2d3ff19860cf911b7b36d0e107f571ecb5addc00614173ad0ac04e6490dc269afbb4041acab2257e2f7e62768e');
EOF
fi
