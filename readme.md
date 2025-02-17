# Linux Desktop Setup Script
`linux` `ubuntu` `script`


Update the local permissions and execute.

```bash
sudo apt install git -y
git clone https://github.com/PreciseNZ/LinuxDesktopSetup.git
cd ./LinuxDesktopSetup
chmod +x setup.sh
sudo ./setup.sh
```
## System Updates
apt Update\
apt Distribution Update\
apt Autoremove & Clean\
Firmware Update\
Disables Network Wait\

## Adds 3rd Party Keys and Repos
JetBrains\
Microsoft Edge\

## Adds PPA's
dotnet/backports (Required for dotnet 9.0)\


## Installs the following Applications
Nala\
Terminator\
Fonts-Powerline\
Git\
Curl\
Python3\
Python3-dotenv\
Solaar\
JetBrains Rider\
JetBrains PyCharm Professional\
Libre Office\
dotnet 8.0 SDK
dotnet 9.0 SDK
Steam

## Additional Configurations
Downloads, unpacks and updates Font Cache for Meslo Nerd Font\
Configures terminator config file for Font
Fixes permissions for home directory to current_user
