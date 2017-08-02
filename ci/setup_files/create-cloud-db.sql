CREATE USER cloud identified by 'cloud';

DROP DATABASE IF EXISTS `cloud`;
CREATE DATABASE `cloud`;
GRANT ALL ON cloud.* to cloud@`localhost` identified by 'cloud';
GRANT ALL ON cloud.* to cloud@`%` identified by 'cloud';

DROP DATABASE IF EXISTS `cloud_usage`;
CREATE DATABASE `cloud_usage`;
GRANT ALL ON cloud_usage.* to cloud@`localhost` identified by 'cloud';
GRANT ALL ON cloud_usage.* to cloud@`%` identified by 'cloud';


GRANT process ON *.* TO cloud@`localhost`;
GRANT process ON *.* TO cloud@`%`;
