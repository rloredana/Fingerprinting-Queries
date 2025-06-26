import win32com.client
from pathlib import Path
import pandas as pd
from datetime import datetime, timedelta
import re

# --- CONFIGURATION ---
DOWNLOAD_DIR = Path("C:/Users/loredana/salesforce_reports/downloads")
INPUT_DIR = Path("C:/Users/loredana/salesforce_reports/input_manual")
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
INPUT_DIR.mkdir(parents=True, exist_ok=True)

SUBJECT_KEYWORDS = [
    "Report results (Active users)",
    "Another Subject to Match"
]
SENDER_KEYWORD = "loredana.raileanu@fluidads.com"
DAYS_BACK = 10

# --- DATE FIXING FUNCTION ---
def fix_date(val):
    if isinstance(val, str):
        val = val.strip()
        # Match MM/DD/YYYY or MM-DD-YYYY, optionally with 12h time (HH:MM AM/PM)
        match = re.match(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:[,\s]+(\d{1,2}):(\d{2})\s*(AM|PM))?$', val, re.IGNORECASE)
        if match:
            mm, dd, yyyy, hour, minute, ampm = match.groups()
            try:
                if hour and minute and ampm:
                    dt_obj = datetime.strptime(f"{mm}-{dd}-{yyyy} {hour}:{minute} {ampm.upper()}", "%m-%d-%Y %I:%M %p")
                    return dt_obj.strftime("%d/%m/%Y, %I:%M %p")
                else:
                    dt_obj = datetime.strptime(f"{mm}-{dd}-{yyyy}", "%m-%d-%Y")
                    return dt_obj.strftime("%d/%m/%Y")
            except ValueError:
                return val
    return val

def reformat_date_column(series):
    return series.apply(fix_date)

# --- CLEAN FILE DATES ---
def clean_file_dates(file_path: Path):
    suffix = file_path.suffix.lower()
    try:
        if suffix == ".csv":
            df = pd.read_csv(file_path, dtype=str, keep_default_na=False)
        else:
            df = pd.read_excel(file_path, dtype=str, engine="openpyxl")

        for col in df.columns:
            original = df[col].copy()
            df[col] = reformat_date_column(df[col])
            if not df[col].equals(original):
                print(f"Formatted date column: {col} in {file_path.name}")

        if suffix == ".csv":
            df.to_csv(file_path, index=False, encoding="utf-8-sig")
        else:
            df.to_excel(file_path, index=False, engine="openpyxl")

        print(f"Updated: {file_path.name}")
    except Exception as e:
        print(f"Failed to process {file_path.name}: {e}")

# --- FETCH FROM OUTLOOK ---
def fetch_outlook_attachments():
    outlook = win32com.client.Dispatch("Outlook.Application").GetNamespace("MAPI")
    inbox = outlook.GetDefaultFolder(6)  # 6 = Inbox
    messages = inbox.Items
    messages.Sort("[ReceivedTime]", True)

    cutoff = datetime.now() - timedelta(days=DAYS_BACK)
    downloaded_files = []

    for message in messages:
        try:
            received_time = message.ReceivedTime.replace(tzinfo=None)
        except:
            continue

        if received_time < cutoff:
            break

        if (
            any(keyword.lower() in message.Subject.lower() for keyword in SUBJECT_KEYWORDS)
            and SENDER_KEYWORD.lower() in message.SenderEmailAddress.lower()
        ):
            attachments = message.Attachments
            for i in range(attachments.Count):
                attachment = attachments.Item(i + 1)
                if attachment.FileName.endswith((".csv", ".xlsx", ".xls")):
                    save_path = DOWNLOAD_DIR / attachment.FileName
                    attachment.SaveAsFile(str(save_path))
                    print(f"Saved from email: {save_path.name}")
                    downloaded_files.append(save_path)

    if not downloaded_files:
        print("No matching emails with attachments found.")
    return downloaded_files

# --- MAIN ENTRY POINT ---
def main(mode="email"):
    if mode == "email":
        files = fetch_outlook_attachments()
    elif mode == "folder":
        files = list(INPUT_DIR.glob("*.csv")) + list(INPUT_DIR.glob("*.xlsx")) + list(INPUT_DIR.glob("*.xls"))
        if not files:
            print(f"No files found in folder: {INPUT_DIR}")
            return
    else:
        print("Invalid mode. Use 'email' or 'folder'.")
        return

    for file_path in files:
        clean_file_dates(file_path)

if __name__ == "__main__":
    # Change between "email" or "folder"
    main(mode="email")