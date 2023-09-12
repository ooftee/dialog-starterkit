# dialog-starterkit

In todays corporate world, the demand for expeditious processes is paramount, alongside a keen emphasis on customization. 
Enter Starter Kits, a solution tailored to this need.

Starter Kits offer a streamlined approach, enabling admin to use a single build profile for all computers. 
Users are then empowered to efficiently install multiple applications with just a few clicks.

This bash script allows users to install apps in bulk using custom jamf triggers with the option to skip any apps they don't want.

## Things to look for

The working directory is `/Library/Management/Dialog-SarterKit`
This is where icons and logs will be stored.

### Define your Array

The `APPS` array is the mos important part of the script, it defines which apps you want to install and how to detect if it was installed succesfully or not.
Each app requires 3 variables:
- FriendlyName: THe name of the app that will be displayed in the list
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
