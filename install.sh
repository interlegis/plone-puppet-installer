#!/bin/bash

usage()
{
cat << EOF
usage: $0 options

This script installs a Plone 4 (database and application) server.

OPTIONS:
   -h      Show this message
   -z      Installs ZEO database server only.
   -a      IP Address of the ZEO Server, in case of a ZEO Client only server.
   -n      Number of ZEO Clients to deploy. Defaults to 1.
   -v      Verbose
EOF
}

confirm()
{
    echo -n "$@ "
    read -e answer
    for response in y Y yes YES Yes Sure sure SURE OK ok Ok
    do
        if [ "_$answer" == "_$response" ]
        then
            return 0
        fi
    done

    # Any answer other than the list above is considerred a "no" answer
    return 1
}

ZEOIP="127.0.0.1"
ZEOONLY=false
CLIENTN=1
VERBOSE=
while getopts “hzn:a:v” OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         a)
             ZEOIP=$OPTARG
             ;;
         n)
             CLIENTN=$OPTARG
             ;;
         z)
             ZEOONLY=true
             ;;
         v)
             VERBOSE=1
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

prereq() 
{
  #install prerequisites
  echo Installing prerequisites, Puppet and Git...
  apt-get update > /dev/null 2>&1
  apt-get install -y git puppet > /dev/null 2>&1
  gem install r10k > /dev/null 2>&1
  
  mkdir -p /etc/puppet/hieradata
  cp -f puppet/hiera.yaml /etc/puppet/
  cp -f puppet/Puppetfile /etc/puppet/
  cp -f puppet/hieradata/*.yaml /etc/puppet/hieradata/
  cp -f puppet/manifests/site.pp /etc/puppet/manifests/
  mkdir -p /etc/facter/facts.d 
}

puppetmodules()
{
  echo "Installing Puppet modules..."
  cd /etc/puppet
  r10k puppetfile install
}

installzeo()
{
  echo "server_role=zeoserver" > /etc/facter/facts.d/role.txt
  puppetmodules
  echo "Installing ZEO Database Server..."
  puppet apply /etc/puppet/manifests/site.pp
  if [ $? -eq 0 ]; then
    echo "ZEO Server should be listening at port 2500."
  else
    echo "An error ocurred while installing the ZEO Server."
    exit 1
  fi
}

installzeoclient()
{
  echo "server_role=appserver" > /etc/facter/facts.d/role.txt
  echo "db_host=$ZEOIP" >> /etc/facter/facts.d/role.txt
  echo "number_instances=$CLIENTN" >> /etc/facter/facts.d/role.txt
  puppetmodules
  echo "Installing Plone Application Server..."
  puppet apply /etc/puppet/manifests/site.pp   
  if [ $? -eq 0 ]; then
    echo "Plone instances installation suceeded. Listening ports:"
    sleep 5
    netstat -tunap |grep python|grep 82..
    echo "Default admin password is admin."
    echo "Happy Ploning!"
  else
    echo "An error ocurred while installing the Application Server."
    exit 1
  fi
 
}

# Check Operating System
ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian  # XXX or Ubuntu??
    VER=$(cat /etc/debian_version)
elif [ -f /etc/redhat-release ]; then
    # TODO add code for Red Hat and CentOS here
    ...
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

echo "Checking compatibility with operating system: $OS $VER..."
if [ "$OS" != "Ubuntu" ] && [ "$VER" != "14.04" ] 
then
  echo "$OS $VER system not supported. Currently tested only in Ubuntu 14.04 LTS (Trusty Tahr)."
fi

#if [[ -z $ZEOSERVER ]] 
#then
#     usage
#     exit 1
#fi

set -o errexit
if $ZEOONLY 
then
  confirm "Do you want to install only the ZEO Database server [y|N]?"
  prereq
  installzeo
else
  if [[ -z $ZEOSERVER ]]
  then 
    confirm "Do you want to install a Plone all-in-one server with $CLIENTN instance(s) [y|N]?"
    prereq
    installzeo
    installzeoclient 
  else
    confirm "Do you want to install $CLIENTN ZEO Client instances for Plone [y|N]?"
    installzeoclient
    prereq
  fi
fi

