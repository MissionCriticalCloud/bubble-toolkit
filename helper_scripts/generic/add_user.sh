#!/bin/sh
#  Add your user account to a specific vm
#
# Usage ./add_user.sh -h <vmname>
#
RUSER=root
RPASS=password
TMPFILE=/tmp/${$}.sh
while getopts "h:" opt; do
  case $opt in
    h)
      HNAME=$OPTARG
      echo Got here $HNAME
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

if [ -z "$HNAME" ]
then
	echo Usage $0 -h '<hostname>'
	exit 1
fi

echo "KEY='" > $TMPFILE
cat ${HOME}/.ssh/authorized_keys | sed -e '/^#/d' -e '/^\s*$/d' >> $TMPFILE
echo "'" >> $TMPFILE

cat << RSCRIPT >> ${TMPFILE}
useradd ${LOGNAME}
ADIR=/home/$LOGNAME/.ssh
AFIL=\$ADIR/authorized_keys
mkdir -p \$ADIR
chown -R ${LOGNAME} \$ADIR
chmod 700 \$ADIR
echo \$KEY > \$AFIL
chown ${LOGNAME} \$AFIL
chmod 400 \$AFIL
echo "${LOGNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RSCRIPT

sudo yum install -y sshpass
sshpass -p $RPASS scp -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no $TMPFILE root@${HNAME}:adduser.sh
if [ "$?" -ne "0" ]
then
	echo "Could not connect to $HNAME" >&2
fi
sshpass -p $RPASS ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no root@${HNAME} "sh ./adduser.sh"
