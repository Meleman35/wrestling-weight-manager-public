# Wrestling Manager 0.20.53

Shared invitations previously opened the full app, which has no Open Graph branding and exceeds Apple's 1 MB preview-page guideline. This release adds a small `join.html` page with Wrestling Manager metadata and the existing WM icon. Browsers continue immediately to the existing app, preserving the complete query and fragment; a button remains if automatic navigation is blocked.

New copied/shared team join codes and organization, staff, athlete, guardian and family invitations use this entry page. The organization email endpoint uses the same page. Existing invitation tokens and links remain valid. No account, membership, permission, subscription or acceptance logic changes. No real invitations are created or sent during validation.

The preview is generic: no recipient, athlete, organization name or token is placed in metadata. The image is hosted alongside the app. A no-referrer policy prevents the private URL from becoming an asset referrer.

The existing icon comes from Damon's Interlocking WM wrestling emblem artwork; it is copied unchanged, not regenerated. The app's main page also receives app-name/image metadata and an icon.

Validation: static metadata/resource-size checks, seven exact forwarding cases, a blocked-navigation fallback, web/native URL helpers, nine existing source checks, ten position-invitation DOM checks and seven fake-transport email checks. No physical Messages preview or native build result is claimed. Previously sent Messages may retain their original previews; test a newly copied link.

The URL host remains GitHub Pages until the separately requested `theteammanager.app` domain connection is completed. Adding preview metadata alone cannot change the visible host name.

References:
- https://developer.apple.com/documentation/technotes/tn3156-create-rich-previews-for-messages
- https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site
