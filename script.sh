#!/bin/bash

##Prerequisites
prereq_list=(
 c-ares
 libicu
 httpd
 openssl
 java-1.8.0-openjdk
 libreoffice-core
 libreoffice-writer
 libreoffice-calc
 xorg-x11-fonts-misc
 xorg-x11-fonts-75dpi
 postgresql-server
 postgresql-contrib
)

##Functions
#Draws a border around a text
border () {
        echo
        local str="$*"
        local len=${#str}
        local i
        for (( i = 0; i < len + 4; ++i )); do
                printf '-'
        done
        printf "\n| $str |\n"
        for (( i = 0; i < len + 4; ++i )); do
                printf '-'
        done
        echo
}

#Installation of a package if it is not already installed
cond_exec () {
        echo " Installing $1..."
        if [[ $(yum list installed | grep $1) ]]; then
                echo " ...$1 is already installed with $(yum info $1 | grep "Version     : " | head -1)"
        else
                yum install -y $1
                echo " ...Done with $1 installation"
        fi
}

#Backup or restore the system to specified path
backup_restore () {
        #Checks if path is valid
        echo "Enter a valid path :"
        read path
        until [[ -d $path ]]; do
                echo -e "$path is not a valid path. Try again.\n"
                read path
        done
        echo -e "The path chosen is $path\n"
        
        #Backup using Rsync
        if [[ $1 == '-b' ]]; then
                border "Backup the system to $path"
                rsync -aAXv / --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/home/bckp/*"} $path
        
        #Restore using Rsync    
        elif [[ $1 == '-r' ]]; then
                read -p "Are you sure you want to restore the system? " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                        border "Restore the system from $path"
                        rsync -aAXv $path --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/home/bckp/*"} /
                        echo " ...Done with system restore from $path"
                else
                        echo " The system restore could not be completed."
                fi
        fi      
}

#Installation of the prerequisites based on the prereq_list array
prereq_install () {
        border "System update"
        echo " Updating the system..."
        yum -y update
        echo " ...Done with update"

        for i in ${prereq_list[@]}; do
                border "$i installation"
                cond_exec "$i"
        done

        border "Check if Library C can support TLS mode"
        if [[ $(uname -a | grep xen) ]]; then
                echo " ...Library C does not support Thread Local Storage mode"
        else
                echo " ...Everything is good"
        fi

        border "Set SELINUX to disabled"
        sed -i 's/SELINUX=enabled/SELINUX=disabled/g' /etc/selinux/config 
        echo " ...Done"

        border "Disable Automatic JDK update functions"
        echo exclude=java-1.8.0-openjdk* >> /etc/yum.conf
        echo " ...Done"
}

#Configuration of postgres database
db_setup () {
        border "Start the postgres server and make it boot on startup"
        systemctl start postgresql
        systemctl enable postgresql

        border "Initialization of database"
        if [[ $(postgresql-setup initdb | grep "Data directory is not empty!") ]]; then
                echo " ...Done with database initialization."
        fi
        border "Modify pg_hba.conf"
        sed -i 's@host    all             all             127.0.0.1/32            ident@host    all             all             127.0.0.1/32            md5@g' /var/lib/pgsql/data/pg_hba.conf
        sed -i 's@host    all             all             ::1/128                 ident@host    all             all             ::1/128                 md5@g' /var/lib/pgsql/data/pg_hba.conf
        echo " ...Done with pg_hba.conf modification."
        
        border "Modify postgresql.conf"
        sed -i 's/#listen_addresses = 'localhost'/listen_addresses = '*'/g' /var/lib/pgsql/data/postgresql.conf
        echo " ...Done with postgresql.conf modification."

        border "Change the postgres LINUX user password"
        passwd postgres
        echo " ...Done with postgres user password update."

        border "Change the postgres DATABASE user password"
        echo "Changing password for database user postgres."
        echo "New password: "
        read -s passwrd
        echo "Retype new password: "
        read -s passwrd_confirm
        until [[ "$passwrd" == "$passwrd_confirm" ]]; do
                echo "Sorry, passwords do not match."
                echo "New password: "
                read -s passwrd;
                echo "Retype new password: "
                read -s passwrd_confirm
        done
        #psql -U postgres -c "ALTER USER postgres WITH PASSWORD '$passwrd';"
        # 
        #export PGPASSWORD='password'
        #psql -h 'server name' -U 'user name' -d 'base name' \
        #-c 'command' (eg. "select * from schema.table")
        echo " ...Done with postgres database password update."
}

#Installation and configuration of Adobe Campaign server
ac_install () {
        #RPM package installation
        border "Adobe Campaign server installation"
        echo -e "Please specify the path of the Adobe Campaign server RPM package: "
        read ac_path
        until [[ $(ls $ac_path | grep nlserver*) ]]; do
                if [[ -d $ac_path ]]; then
                        echo -e "$ac_path does not contain the Adobe Campaign server RPM package."
                fi
                echo -e "Try again.\n"
                read ac_path
        done
        echo $(ls $ac_path | grep nlserver*)
        rpm -Uvh $ac_path/$(ls $ac_path | grep nlserver*)
        
        border "Start the Neolane server and make it boot on startup"
        /etc/init.d/nlserver6 start
        /sbin/chkconfig nlserver6 on
        echo " ...Done."        

        #Post-installation configuration
        border "Creation of environment variables"
        echo "export OOO_BASIS_INSTALL_DIR=/usr/lib64/libreoffice;
        export OOO_INSTALL_DIR=/usr/lib64/libreoffice;
        export OOO_URE_INSTALL_DIR=/usr/lib64/libreoffice/share

        export JDK_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.171-8.b10.el7_5.x86_64/jre/lib/amd64

        export LD_LIBRARY_PATH=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.171-8.b10.el7_5.x86_64/jre/lib/amd64:/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.171-8.b10.el7_5.x86_64/jre/lib/amd64/server

        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.171-8.b10.el7_5.x86_64/jre/lib/amd64

        export NEOLANE_HOME=/usr/local/neolane" >> /usr/local/neolane/nl6/customer.sh
        echo " ...Done with environment variables creation."    

        border "Configuration of the security zone to public and HTTP"
        cd /usr/local/neolane/nl6/conf/
        cp serverConf.xml serverConf.xml.origin
        sed -i 's@<xtk internalPassword="" internalSecurityZone="lan"/>@<xtk internalPassword="" internalSecurityZone="public"/>@g' serverConf.xml
        sed -i 's@<securityZone allowDebug="false" allowHTTP="false"@<securityZone allowDebug="false" allowHTTP="true"@g' serverConf.xml
        systemctl restart nlserver6
        echo " ...Done with security zone modifications."

        border "Change of ownership of neolane folder"     
        cd /usr/local/
        chmod +x neolane/nl6/customer.sh
        chown -R neolane:neolane neolane
        chmod -R 775 neolane
        chmod 755 neolane
        echo " ...Done with Neolane folder change of ownership."
        echo -e "\nTBC ..."
        
        #border "Change the default internal password"
        #su neolane -c "nlserver config -internalpassword"
        #echo " ...Done with internal password change."

        #border "Restart the server and test it as Neolane user"
        #nlserver start web
              #sudo su root
}


#Program starts here
clear
cat << "EOF"
               _         _                                   
     /\       | |       | |                                  
    /  \    __| |  ___  | |__    ___                         
   / /\ \  / _` | / _ \ | '_ \  / _ \                        
  / ____ \| (_| || (_) || |_) ||  __/                        
 /_/    \_\\__,_| \___/ |_.__/  \___|                        
      _____                                 _                
     / ____|                               (_)               
    | |      __ _  _ __ ___   _ __    __ _  _   __ _  _ __   
    | |     / _` || '_ ` _ \ | '_ \  / _` || | / _` || '_ \  
    | |____| (_| || | | | | || |_) || (_| || || (_| || | | | 
     \_____|\__,_||_| |_| |_|| .__/  \__,_||_| \__, ||_| |_| 
                             | |                __/ |        
         _____              _|_|       _  _    |___/         
        |_   _|            | |        | || |                 
          | |   _ __   ___ | |_  __ _ | || |  ___  _ __      
          | |  | '_ \ / __|| __|/ _` || || | / _ \| '__|     
         _| |_ | | | |\__ \| |_| (_| || || ||  __/| |        
        |_____||_| |_||___/ \__|\__,_||_||_| \___||_|

                                  
EOF

#warning = $(tput bold Dont forget to be root!)
bold=$(tput bold)
normal=$(tput sgr0)             

echo -e "Welcome to the Adobe Campaign Installer!\n\nThis program aims to automate the process of installing adobe campaign of a linux server using a postgres database.\n\nThe Adobe Campaign server installation file should be accessible in […]\Dropbox (Munvo)\Delivery Adobe\Adobe Folders\Software\AC v7. The Windows client with the same build number (8886) is also included in the folder.\n\nYou can adapt this program by modifying the the prerequisite list (prereq_list).${bold}Dont forget to run the script as root!${normal} (sudo su root)\n"

PS3="
I want to... (to list the options, choose 1) "

options=("List the options" "Backup the system" "Restore the system" "List the prerequisites" "Install the prerequisites" "Setup the postgres database" "Install Adobe Campaign" "Quit")

select opt in "${options[@]}"
do
case $opt in
        "List the options")
                echo -e "...you chose to $opt.\n" | tr '[:upper:]' '[:lower:]'
cat << "EOF"

1) List the options             5) Install the prerequisites
2) Backup the system            6) Setup the postgres database
3) Restore the system           7) Install Adobe Campaign
4) List the prerequisites       8) Quit
                
EOF
                ;;
        "Backup the system")
                echo "...you chose to $opt.\n" | tr '[:upper:]' '[:lower:]'
                backup_restore -b
                echo " ...Done with system backup to $path"
                ;;
        "Restore the system")
                echo "...you chose to $opt.\n" | tr '[:upper:]' '[:lower:]'
                backup_restore -r
                echo " ...Done with system restore from $path"
                ;;
        "List the prerequisites")
                echo "...you chose to $opt.\n" | tr '[:upper:]' '[:lower:]'
                printf '%s\n' "${prereq_list[@]}"
                ;;
        "Install the prerequisites")
                echo "...you chose to $opt." | tr '[:upper:]' '[:lower:]'
                prereq_install
                echo " ...Done with the prerequisite installation."
                ;;
        "Setup the postgres database")
                echo "...you chose to $opt.\n" | tr '[:upper:]' '[:lower:]'
                db_setup
                echo " ...Done with database setup."
                ;;
        "Install Adobe Campaign")
                echo "...you chose to $opt.\n" | tr '[:upper:]' '[:lower:]'
                ac_install
                echo " ...Congratulation, you are done with Adobe Campaign installation!"               
                ;;
        "Quit")
                echo "Thanks for using my program!"
                break
                ;;
        *) echo -e "Invalid option $REPLY";;
esac
done
