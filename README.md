# dialog-starterkit

This is a script to install apps in bulk using custom jamf triggers.

Users have the option to skip any apps they don't want.

## Things to look for

The working directory is ''/Library/Management/Dialog-SK''

### Icons

Icons are cashed locally, please provide a public URL to download them from.
Make sure the icon name is the same as the jamf custom trigger.

### Branding

Replace the icon argument in the 'START_JSON' and 'INSTALL_JSON' with your company logo.

### Requirements

This script uses SwiftDialog and JQ, it requires the policies 'install_swiftdialog' and 'install_jq' to exists.

<img width="932" alt="dialog_starterkit-01" src="https://github.com/ooftee/dialog-starterkit/assets/88021434/3298f471-8971-4f1a-ab04-1f3eea194401">
<img width="932" alt="dialog_starterkit-02" src="https://github.com/ooftee/dialog-starterkit/assets/88021434/4138fb4e-e9f1-4304-b55a-f1b1bb7e3fbb">
