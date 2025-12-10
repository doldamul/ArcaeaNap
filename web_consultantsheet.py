import os
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from configuration import config

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive.file",
]

def open_sheet():
    creds = get_creds()
    print('creds: ', creds)
    
def get_creds():
    token_filename = 'token.json'
    token_filepath = os.path.join(config['general']['cache_path'], token_filename)
    
    secret_filename = 'client_secret.json'
    secret_filepath = os.path.join(config['general']['cache_path'], secret_filename)
    
    creds = None
    if os.path.exists(token_filepath):
        creds = Credentials.from_authorized_user_file(token_filepath, SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                secret_filepath, SCOPES
            )
            creds = flow.run_local_server(port=0) # TODO: mannually open URL to set the browser as configuration, and handle the redirect
        with open(token_filepath, "w") as token:
            token.write(creds.to_json())
    return creds

if __name__ == "__main__":
    open_sheet()