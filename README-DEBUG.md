# Debug Configuration

For faster development/testing, you can create a `debug-config.json` file in the project root with your source credentials. This file is gitignored and will auto-load all sources on app startup.

## Setup

1. Copy the example file:
```bash
cp debug-config.json.example debug-config.json
```

2. Edit `debug-config.json` with your sources:
```json
{
  "sources": [
    {
      "name": "My Xtream Source",
      "type": "xtream",
      "xtreamUrl": "https://your-server.com",
      "username": "your_username",
      "password": "your_password"
    },
    {
      "name": "My M3U Playlist",
      "type": "m3u",
      "m3uUrl": "https://example.com/playlist.m3u"
    },
    {
      "name": "My Stalker Portal",
      "type": "stalker",
      "stalkerUrl": "http://example.com/stalker_portal/c/",
      "mac": "00:1A:79:00:00:00",
      "username": "optional-login",
      "password": "optional-password"
    }
  ]
}
```

You can have multiple M3U, Xtream, or Stalker sources. Just add/remove objects from the `sources` array. For a Stalker portal, `username` and `password` are optional and only needed when the portal asks for a login in addition to the MAC address.

3. Run the app - all your sources will be automatically loaded!

**Note:** This file is gitignored and will never be committed to the repository.
