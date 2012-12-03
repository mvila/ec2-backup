# ec2-backup

Easy backup your EC2 instances.

`ec2-backup` creates snapshots of all attached volumes of an EC2 instance
and automatically purges snapshots that not correspond to:

* the last 10 days,
* the last 10 mondays,
* the first day of the last 10 months.

**Important:** in order to properly select which snapshot to purge,
`ec2-backup` should be run daily.

## Installation

    $ sudo npm -g install coffee-script
    $ npm install ec2-backup

## Configuration

  Edit the `config.json` to set up your AWS credentials.

## Usage

    Usage: ec2-backup

    Options: no option for now.

To automatically launch `ec2-backup` each night, you can add a cron job
with `crontab -e`: 

    0 4 * * * /path/to/ec2-backup.coffee >> /var/log/ec2-backup.log 2>&1

## License

  MIT