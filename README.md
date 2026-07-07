<div align="center">

<img width="80%" src="https://github.com/doldamul/ArcaeaNap/blob/main/docs/assets/screenshots/1.png">

<h1>
  <img width="3%" src="https://github.com/doldamul/ArcaeaNap/blob/main/docs/assets/logo.png">
  ArcaeaNap
</h1>

<h3>
An arcaea online based play record viewer.
</h3>

[Website](https://doldamul.github.io/ArcaeaNap/) &nbsp;&nbsp;&nbsp; [Privacy Policy](https://doldamul.github.io/ArcaeaNap/privacy_policy/) &nbsp;&nbsp;&nbsp; [Terms of Service](https://doldamul.github.io/ArcaeaNap/terms_of_service/)

English · [한국어](./README.ko.md)

</div>

ArcaeaNap is a fast and convenient Arcaea play record viewer. It saves Arcaea Online data to your local PC and provides various play records, such as total play time and play counts per song, through an intuitive UI.

**Notice and Usage Conditions:**

- An active **Arcaea Online subscription** is required to save your play records.
- A **Google account** is required to generate the song information database.
- **1GB+ of free disk space** is required for caching song thumbnails and the Playwright browser.
- Windows 10+ and macOS 14+ (Apple Silicon) environments are supported.

## Features

- `View Statistics`: Check your play time and top play rankings at a glance.
- `Explore Records`: Quickly explore records stored on your PC with filtering, sorting, and search functions.
- `Send Records to Arcaea Consultant Sheet`: Easily send your locally stored records to a Arcaea Consultant Sheet in batches.

## Usage

1. Download the program archive from the [Releases](https://github.com/doldamul/ArcaeaNap/releases) page.
2. The execution method depends on your operating system:
   - **Windows:** Extract the archive and run the `ArcaeaNap.exe` file inside the program directory.
   - **macOS:** After extracting the archive, open the Terminal app and type the following:
     ```bash
     xattr -cr 
     ```
     (There must be a space after `-cr`)

     Then drag and drop the extracted `ArcaeaNap.app` file into the terminal window. It will look something like this:
     ```bash
     xattr -cr /Users/username/Downloads/ArcaeaNap.app
     ```
     Press Enter. Once the process is complete, move the app to the `/Applications` folder and run it.
3. Log in with your Google account and generate the song information database.
4. Download the browser for data analysis from the Settings.
5. In Settings, log in to Arcaea Online and ensure your subscription is active.
6. Click the Start Analysis button in the Analyze tab to access Arcaea Online.
7. Wait a moment on the play record page. The browser will automatically detect your play records and song jacket images, saving them to your local PC.
8. Visit all pages for each difficulty. Be careful that no new records from Arcaea are registered during this time.
9. Explore your play records in the Home and Statistics tabs.

After the initial setup, you only need to visit the pages for your latest play records.
Once all updates since the last saved record have been viewed, the Synchronization Status in the Analyze tab will be updated.

## Build

- Python 3.13+
- Install required dependencies:
  ```bash
  pip install PyQt6 playwright requests beautifulsoup4 google-auth google-auth-oauthlib google-api-python-client gspread keyring pywin32-ctypes cx_Freeze
  playwright install chromium
  ```

To run the application from the source code, run `main.py`:

```bash
python main.py
```

This project uses `cx_Freeze` to build the standalone executable.

For Windows:
```bash
python setup.py build
```

For macOS:
```bash
python setup.py bdist_mac
```

A valid `client_secret.json` (Google Cloud API credentials) is required in the project root directory when running or building the application.
Here are the steps to generate the `client_secret.json` file:

1. Create a new project in the [Google Cloud Console](https://console.cloud.google.com).
2. Open the sidebar and navigate to `APIs & Services > Credentials`.
3. Create an OAuth client ID with the `Desktop app` application type.
4. Click the "Add secret" button to generate a client secret, then click the "Download JSON" button to download it.
5. Rename the downloaded JSON file to `client_secret.json`.
6. Create an API key with API restrictions set to Google Picker API and Google Sheets API.
7. Click the "Show key" button, copy the API key, and add the following parameter to `client_secret.json`:

```json
{
  "installed": {
    ...
    "api_key": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  }
}
```

## License & Copyright

- This project is licensed under the [GNU GPL v3.0](./LICENSE).
- Arcaea and all related assets are the property of lowiro. All rights reserved.
