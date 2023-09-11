# dialog-starterkit

This is a script to install apps in bulk using custom jamf triggers.

Users have the option to skip any apps they don't want installed.

## Things to look for

The working directory is /Library/Management/Dialog-SK

### Icons

Icons are cashed locally, please provide a public URL to download them from.
Make sure the icon name is the same as the jamf custom trigger.

### Branding

Make sure to replace the icon argument in the START_JSON and INSTALL_JSON with your company logo.

### Requirements

This script uses SwiftDialog and JQ, please make sure the install_swiftdialog and install_jq policy exists.

