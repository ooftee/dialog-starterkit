# dialog-starterkit

Starter Kits provide end users with a simple and intuitive way to select and install a group of Apps relevant to their role. 
Best of all, the user can continue with other tasks while the Apps are installed in the background.

For MacAdmins, using Starter Kits allows you to keep the enrolment process lean, fast and generic.
Why maintain multiple enrolment workflows when users can simply use a Starter Kit to get the Apps they need?

Starter Kits is a bash script that uses JQ and SwiftDialog under the hood. Admins only need to configure an array of App definitions. The user is presented with the options and can toggle on/off the Apps they want to install. The script also includes logic to skip Apps that are already installed. 


# Configuration

### Working Directory

The script uses a working directory to store icons and logs at the path: 

`/Library/Management/Dialog-SarterKit`

Due to the use of JQ and single quotes, changing this path would you to modify the main script.

### Define your Array

The `APPS` array is the most important part of the script, it defines which apps you want to install and how to detect if it was installed successfully or not.
Each app requires 3 variables:
- FriendlyName: The friendly name of the App that will be displayed in the list to the user
- Location: Where the App gets installed, this is used to detect if the App is already installed and validate the installation
- JamfTrigger (and IconName): Custom event trigger in JAMF and also the icon name (see below)

For example:
```bash
APPS=(
  "iTerm,/Applications/iTerm.app,install_iterm"
  "GitHub Desktop,/Applications/GitHub Desktop.app,install_githubdesktop"
)
```

### Icons

Icons are cashed locally, please provide a public URL to download them from.
A typical way of doing this is to use an Public Amazon S3 bucket.
Make sure the icon name is the same as the JAMF custom trigger.

For example, if your policy trigger is `install_iterm` make sure the icon is named `install_iterm.png`

### Branding

Due to the use of JQ and single quotes, variables can't be used in `START_JSON` and `INSTALL_JSON`.
It's recommended to replace the icon argument in there with your company logo.
Feel free to change the message and title to fit your corporate messaging style.

### Requirements

This script uses SwiftDialog and JQ. 
Please ensure those are installed in the standard `/usr/local/bin` folder.
If the script is unable to find the binaries, it will attempt to install them with these custom triggers `install_swiftdialog` and `install_jq`, which you can modify in the script variables.

<img width="932" alt="dialog_starterkit-01" src="https://github.com/ooftee/dialog-starterkit/assets/88021434/3298f471-8971-4f1a-ab04-1f3eea194401">
<img width="932" alt="dialog_starterkit-02" src="https://github.com/ooftee/dialog-starterkit/assets/88021434/4138fb4e-e9f1-4304-b55a-f1b1bb7e3fbb">
