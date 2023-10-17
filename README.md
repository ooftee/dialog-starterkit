# dialog-starterkit

Starter Kits provide end users with a simple and intuitive way to select and install a group of Apps relevant to their role. 
Best of all, the user can continue with other tasks while the Apps are installed in the background.

For MacAdmins, using Starter Kits allows you to keep the enrolment process lean, fast and generic.
Why maintain multiple enrolment workflows when users can simply use a Starter Kit to get the Apps they need?

Starter Kits is a bash script that uses JQ and SwiftDialog under the hood. Admins only need to configure an array of App definitions. The user is presented with the options and can toggle on/off the Apps they want to install. The script also includes logic to skip Apps that are already installed. 
This bash script allows users to install apps in bulk using custom jamf triggers with the option to skip any apps they don't want.

## Working Directory

The script uses a working directory to store icons and logs.
The path is `/Library/Management/Dialog-SarterKit`

### Define your Array

The `APPS` array is the most important part of the script, it defines which apps you want to install and how to detect if it was installed successfully or not.
Each app requires 3 variables:
- FriendlyName: The name of the app that will be displayed in the list
- Location: Where the app gets installed, this is used to validate the installation
- JamfTrigger&IconName: Custom event trigger in jamf, also the icon name (see below)

ie: iTerm,/Applications/iTerm.app,install_iterm

### Icons

Icons are cashed locally, please provide a public URL to download them from.
Make sure the icon name is the same as the jamf custom trigger.

for example if your policy trigger is `install_iterm` make sure the icon is named `install_iterm.png`

### Branding

Due to the single quoting, variable can't be used in `START_JSON` and `INSTALL_JSON`.
It is recommended to replace the icon argument in there with your company logo.
Feel free to change message and title to fit your corporate messaging style.

### Requirements

This script uses SwiftDialog and JQ. 
Please ensure those are installed in the /usr/local/bin folder.
If the script is unable to find the binaries it will attempt to install them with these custom triggers `install_swiftdialog` and `install_jq`.

<img width="932" alt="dialog_starterkit-01" src="https://github.com/ooftee/dialog-starterkit/assets/88021434/3298f471-8971-4f1a-ab04-1f3eea194401">
<img width="932" alt="dialog_starterkit-02" src="https://github.com/ooftee/dialog-starterkit/assets/88021434/4138fb4e-e9f1-4304-b55a-f1b1bb7e3fbb">
