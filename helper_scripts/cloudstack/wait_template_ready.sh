#!/bin/bash

function check_templates {
  cloudmonkey list templates templatefilter=all | grep isready | grep --quiet False
  return $?
}

check_templates
while [ $? -ne 1 ]; do
  date | tr -d '\n'
  echo ": Templates not ready, waiting.."
  sleep 15
  check_templates
done

# Ready
date | tr -d '\n'
echo ": Templates ready!"
