#!/bin/bash

################################
# Initial OpenVPN installation #
# Created by: Tod Lazarov      #
# Version: 0.8                 #
# Created on: Aug 10th 2017    #
# Last Edited: Sept 28th 2017  #
################################

#===============================================================================================================#
# MAIN                                                                                                          #
#===============================================================================================================#
function main()
{
    # Check if the script/installation has been ran
    check_if_ran
    
    # User input
    push_route_user_input
    hostname_user_input

    echo "Note: User's list should be in a text file, one line per user name,"
    echo "in the naming convention you expect to be used"
    echo "Ex. Adam_Cooper // Firstname_Lastname"
    echo "Do you have the client's user list? (yes|YES|y)"

    read -r check_user_list
    
    echo "----------------------------------------------------------------"

    if [ $check_user_list = "yes" ] || [ $check_user_list = "YES" ] || [ $check_user_list = "y" ] || [ $check_user_list = "Yes" ]; then
        echo "Please provide the full path to the file that contains the users names"
        read -r user_list

        # Install
        install_openvpn_easy_rsa
        install_server_conf
        install_server_keys_certificates
        install_config_tpl
        install_generate_key_ovpn_script
        install_users
        install_Plexxis_Admin_user
        
        # Logs and service start
        create_log_folder_and_start_service
 
        # Checks and logs
        create_confirmation_file_and_log

    else
        # Install
        install_openvpn_easy_rsa
        install_server_conf
        install_server_keys_certificates
        install_config_tpl
        install_generate_key_ovpn_script
        install_Plexxis_Admin_user
        
        # Logs and service start
        create_log_folder_and_start_service
 
        # Checks and logs
        create_confirmation_file_and_log       
    fi
}
#===============================================================================================================#
# Check if the script has already been ran                                                                      #
#===============================================================================================================#
function check_if_ran()
{
    if [ -e /etc/openvpn/.openvpn_install_check ]; then
            echo "The installation was already ran"
            echo "Please confirm"
            exit 2
    fi
}

#===============================================================================================================#
# User input checks                                                                                             #
#===============================================================================================================#
function push_route_user_input()
{
    echo "What is the push route for this Client's VPN > "
    read -r push_route
    
    # Validate IP address
    if [ "$(ipcalc -c $push_route 2>&1 > /dev/null)" != "" ]; then
        echo "Incorrect IP"
        exit 1
    fi
    
    echo "----------------------------------------------------------------"
}

function hostname_user_input()
{
    echo "Please provide the hostname > "
    read -r cloud_hostname
    
    # Validate hostname address
    nslookup $cloud_hostname 1> /tmp/.hostname_look_up
    TEST_HOSTNAME=$(grep find /tmp/.hostname_look_up)
    if [[ $TEST_HOSTNAME != "" ]]; then
        echo "Invalid Hostname"
        exit 1
    fi

    rm -rf /tmp/.hostname_look_up
    
    echo "----------------------------------------------------------------"
}

#===============================================================================================================#
# Main openvpn and rsa installation                                                                             #
#===============================================================================================================#

#===============================================================================================================
# Generate a random number between MAX($2) and MIN($1) variables
function generate_number()
{
    echo $(( ( RANDOM % $2 ) + $1 ))
}

#===============================================================================================================
# Install necessary packages and clean up
function install_openvpn_easy_rsa()
{
    cd /etc/openvpn

    # Variables
    url_addres="BujKbsZp5gtAYt9R.plexxisrnd.com/OVPN/"
    easy_rsa="easy-rsa-2.2.2-1.el6.noarch.rpm"
    openvpn="openvpn-2.4.3-1.el6.x86_64.rpm"
    pkcs11_helper="pkcs11-helper-1.11-3.el6.x86_64.rpm"

    # Get the packages from the server
    wget $url_addres$easy_rsa
    wget $url_addres$openvpn
    wget $url_addres$pkcs11_helper

    # Install the packages
    rpm -Uvh pkcs11-helper-1.11-3.el6.x86_64.rpm easy-rsa-2.2.2-1.el6.noarch.rpm openvpn-2.4.3-1.el6.x86_64.rpm
    
    # Clean up
    rm -f $easy_rsa $openvpn $pkcs11_helper
}

#===============================================================================================================
# Initial setup of server.conf
function install_server_conf()
{
    B=$(generate_number 16 30)
    C=$(generate_number 1 254)

    cat <<- _EOF_ > /etc/openvpn/server.conf
        port 1194
        proto udp
        dev tun0
        comp-lzo

        # client-to-client
        persist-key
        persist-tun
        cipher AES-256-CBC

        # crl-verify rsa/keys/crl.pem
        user nobody
        group nobody

        keepalive 10 120

        ca /etc/openvpn/rsa/keys/ca.crt
        dh /etc/openvpn/rsa/keys/dh2048.pem
        key /etc/openvpn/rsa/keys/server.key
        cert /etc/openvpn/rsa/keys/server.crt

        ifconfig-pool-persist ipp.txt
        status /var/log/openvpn/server.log
        verb 3

        # virtual subnet unique for openvpn to draw client addresses from
        # the server will be configured with x.x.x.1
        # important: must not be used on your network
        server 10.$B.$C.0 255.255.255.0

        # push routes to clients to allow them to reach private subnets
        push "route $push_route 255.255.255.255"
    _EOF_
}

#===============================================================================================================
# Generate keys and certificates
function install_server_keys_certificates()
{
    mkdir -p /etc/openvpn/rsa
    cp -rf /usr/share/easy-rsa/2.0/* /etc/openvpn/rsa

    # Fill in the /etc/openvpn/rsa/vars file with our information
    sed -i -e 's/export KEY_COUNTRY="US"/export KEY_COUNTRY="CA"/g' /etc/openvpn/rsa/vars
    sed -i -e 's/export KEY_PROVINCE="CA"/export KEY_PROVINCE="ON"/g' /etc/openvpn/rsa/vars
    sed -i -e 's/export KEY_CITY="SanFrancisco"/export KEY_CITY="Bolton"/g' /etc/openvpn/rsa/vars
    sed -i -e 's/export KEY_ORG="Fort-Funston"/export KEY_ORG="Plexxis Cloud"/g' /etc/openvpn/rsa/vars
    sed -i -e 's/export KEY_EMAIL="me@myhost.mydomain"/export KEY_EMAIL="sysadmin@plexxis.com"/g' /etc/openvpn/rsa/vars
    sed -i -e 's/export KEY_OU="MyOrganizationalUnit"/export KEY_OU="Plexxis Cloud"/g' /etc/openvpn/rsa/vars

    # Source the file to export the variables and their values
    cd /etc/openvpn/rsa || exit
    source ./vars

    # Run initializing scripts
    ./clean-all

    # Create a Certificate Authority(certificate+key) in /etc/openvpn/rsa/keys/
    yes '' | ./build-ca
    echo -e "\n"

    # Create key and certificate for the server itself. This replaces ./builk-key-server
    ./pkitool --batch --server server

    # Generate Diffie-Hellman file used for information exchange to complement RSA
    # Creates dh2048.pem in /etc/openvpn/rsa/keys/
    ./build-dh
}

#===============================================================================================================#
# Create config.ovpn.tpl, generate_key_ovpn.sh script and install users                                         #  
#===============================================================================================================#

#===============================================================================================================
# Create config.ovpn.tpl
function install_config_tpl()
{
    cat <<- _EOF_ > /etc/openvpn/rsa/config.ovpn.tpl
        client
        dev tun
        proto udp
        remote $cloud_hostname 1194
        resolv-retry infinite
        nobind
        persist-key
        persist-tun
        comp-lzo
        verb 3
        cipher AES-256-CBC
    _EOF_
}

#===============================================================================================================
# Create generate_key_ovpn.sh script
function install_generate_key_ovpn_script()
{
    cat <<- _EOF_ > /etc/openvpn/rsa/generate_key_ovpn.sh
        #!/bin/bash

        # Created on: July 18 2017
        # Last modified: July 18 2017
        cd $(dirname ${BASH_SOURCE[0]})

        read -p "Please type in user name for the new config: " USER
        [ -z ${USER} ] && { echo "Cannot be empty"; exit 1; }
        [ -f keys/${USER}.crt ] && { echo "Certificate keys/${USER}.crt already exists"; exit 2; }

        source ./vars
        ./build-key ${USER}
        
        (
        # This should be existing config template, with only missing certificates, and keys sections.
        cat config.ovpn.tpl
        
        echo '<key>'
        cat keys/${USER}.key
        echo '</key>'

        echo '<cert>'
        cat keys/${USER}.crt
        echo '</cert>'

        echo '<ca>'
        cat keys/ca.crt
        echo '</ca>'
        ) > openvpn_${USER}.ovpn

        mkdir -p /root/OVPN_KEYS
        mv openvpn_${USER}.ovpn /root/OVPN_KEYS/
        echo "OVPN copied to /root/OVPN_KEYS/"
    _EOF_

    chmod 755 generate_key_ovpn.sh
}

#===============================================================================================================
# Install from user list
function install_users()
{
    while read name; do
        cd /etc/openvpn/rsa/ || exit
        [ -z $name ] && { echo "Cannot be empty"; exit 1; }
        [ -f keys/$name.crt ] && { echo "Certificate keys/$name.crt already exists"; exit 2; }

        #source ./vars # The varialbes get sourced during the server installation process
        ./pkitool $name
        
        (
        # This should be existing config template, with only missing certificates, and keys sections.
        cat config.ovpn.tpl
        
        echo '<key>'
        cat keys/$name.key
        echo '</key>'

        echo '<cert>'
        cat keys/$name.crt
        echo '</cert>'

        echo '<ca>'
        cat keys/ca.crt
        echo '</ca>'
        ) > openvpn_$name.ovpn

        mv openvpn_$name.ovpn /root/OVPN_KEYS/
        echo "OVPN copied to /root/OVPN_KEYS/"
    done <$user_list
}
#===============================================================================================================
# Create Plexxis_Admin test user
function install_Plexxis_Admin_user()
{
    cd /etc/openvpn/rsa/ || exit
    [ -z Plexxis_Admin ] && { echo "Cannot be empty"; exit 1; }
    [ -f keys/Plexxis_Admin.crt ] && { echo "Certificate keys/Plexxis_Admin.crt already exists"; exit 2; }

    #source ./vars # Since this is a copy of the user installation script we dont need to source the variables again
    ./pkitool Plexxis_Admin
    
    (
    # This should be existing config template, with only missing certificates, and keys sections.
    cat config.ovpn.tpl

    echo '<key>'
    cat keys/Plexxis_Admin.key
    echo '</key>'

    echo '<cert>'
    cat keys/Plexxis_Admin.crt
    echo '</cert>'

    echo '<ca>'
    cat keys/ca.crt
    echo '</ca>'
    ) > openvpn_Plexxis_Admin.ovpn

    mv openvpn_Plexxis_Admin.ovpn /root/OVPN_KEYS/
    echo "OVPN copied to /root/OVPN_KEYS/"
}

#===============================================================================================================#
# Create a file check, to prevent script from running multiple times                                            #
#===============================================================================================================#
function create_confirmation_file_and_log()
{
    touch /etc/openvpn/.openvpn_install_check
    echo "Last run on $(date)" >> /etc/openvpn/.openvpn_install_check
}

#===============================================================================================================#
# Create logs and start                                                                                         #
#===============================================================================================================#
function create_log_folder_and_start_service
{
    mkdir -p /var/log/openvpn/
    touch /var/log/openvpn/server.log
    
    service openvpn start
    chkconfig openvpn on
}

#===============================================================================================================#
# Call the main function                                                                                        #
#===============================================================================================================#
main
