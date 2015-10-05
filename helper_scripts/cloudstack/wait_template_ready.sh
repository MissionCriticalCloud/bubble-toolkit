#!/bin/bash

function check_templates {
  cloudmonkey list templates templatefilter=all | grep isready | grep --quiet True
  return $?
}

check_templates
while [ $? -ne 0 ]; do
  date | tr -d '\n'
  echo ": Templates not ready, waiting.."
  sleep 5
  check_templates
done

# Ready
date | tr -d '\n'
echo ": Templates ready!"
