#!/bin/bash

echo "This is what I will do on your storage:"
find /data/storage/secondary/*/* | awk {'print "rm -rf " $1'} 
find /data/storage/primary/*/* | awk {'print "rm -rf " $1'} 

echo "Agree to delete? (y/n)"
read storageans
if [ "$storageans" = y ]; then
  echo "You said yes."
  find /data/storage/secondary/*/* | awk {'print "rm -rf " $1'} | sh
  find /data/storage/primary/*/* | awk {'print "rm -rf " $1'} | sh
else
  echo "You said no. Did nothing."
fi

