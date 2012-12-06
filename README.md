# ec2-backup

Easy backup your EC2 instances.

`ec2-backup` creates snapshots of all attached volumes of an EC2 instance
and automatically purges snapshots that not correspond to:

* the last 10 days,
* the last 10 mondays,
* the first day of the last 10 months.

**Important:** in order to properly select purgeable snapshots,
`ec2-backup` should be run daily.

## Installation

    $ sudo npm -g install coffee-script
    $ npm install ec2-backup

## Configuration

Put your AWS credentials in the `config.json` file.

## Usage

    $ ec2-backup

To automatically launch `ec2-backup` every night, just add a cron job
like this: 

    0 4 * * * /path/to/ec2-backup.coffee >> /var/log/ec2-backup.log 2>&1

## License

MIT