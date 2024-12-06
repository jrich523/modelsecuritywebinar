# Model Security Webinar Readme

This repository contains a lot of components to help deliver a talk on model security for audences that may not be familiar with ML or its oddities.

Do not assume any of the code is safe to run at all.

## Setup

Install all the dependencies with:

```bash
pip install -r requirements.txt
```

You'll also need to install tshark in order to run the capture commands:

```bash
# Debian 
sudo apt update
sudo apt install tshark

# RHEL/CentOS
sudo yum install wireshark

# Fedora
sudo dnf install wireshark
```

Lastly you need to create a secret file that has fake AWS secrets within it with:

```bash
cat <<EOF > /tmp/secret_file
[default]
aws_access_key_id = FAKEACCESSKEY123456
aws_secret_access_key = fakesecretkey9876543210FAKE
aws_session_token = faketokenEXAMPLEfaketokenEXAMPLEfaketokenEXAMPLE
EOF
```

## Running the Exercise

Follow the contents of notebook 01.

Before loading the compromised model, in a termianl session on that host run:

```bash
sudo tshark -i any -Y 'http.request and http.host contains "protectai.com"' -T fields -e http.host -e http.request.uri -e http.request.method -e http.file_data
```

Good luck!