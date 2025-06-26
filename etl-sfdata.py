import win32com.client
from pathlib import Path
import pandas as pd
from datetime import datetime, timedelta
import re

# --- CONFIGURATION ---
BASE_DIR = Path("C:/Users/loredana/salesforce_reports")

DOWNLOAD_DIR      = BASE_DIR / "downloads"
INPUT_DIR         = BASE_DIR / "input_manual"
OUTPUT_EMAIL_DIR  = BASE_DIR / "output_email"
OUTPUT_FOLDER_DIR = BASE_DIR / "output_folder"

# Create all folders if not exist
for dir_path in [DOWNLOAD_DIR, INPUT_DIR, OUTPUT_EMAIL_DIR, OUTPUT_FOLDER_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

SUBJECT_KEYWORDS = [
    "Report results (Active users)",
    "Another Subject to Match"
]

SENDER_KEYWORDS = [
    "loredana.raileanu@fluidads.com",
    "integrations@fluidads.com"
]

DAYS_BACK = 10

# --- DATE FIXING FUNCTION ---
def fix_date(val):
    if isinstance(val, str):
        val = val.strip()
        match = re.match(
            r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:[,\s]+(\d{1,2}):(\d{2})\s*(AM|PM))?$',
            val,
            re.IGNORECASE
        )
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
def clean_file_dates(file_path: Path, output_dir: Path):
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

        output_file = output_dir / file_path.name
        if output_file.exists():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = output_file.with_name(f"{output_file.stem}_{timestamp}{output_file.suffix}")

        if suffix == ".csv":
            df.to_csv(output_file, index=False, encoding="utf-8-sig")
        else:
            df.to_excel(output_file, index=False, engine="openpyxl")

        print(f"Cleaned and saved: {output_file.name}")
    except Exception as e:
        print(f"Failed to process {file_path.name}: {e}")

# --- FETCH FROM OUTLOOK ---
def fetch_outlook_attachments():
    outlook = win32com.client.Dispatch("Outlook.Application").GetNamespace("MAPI")
    inbox = outlook.GetDefaultFolder(6)
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
            and any(sender.lower() in message.SenderEmailAddress.lower() for sender in SENDER_KEYWORDS)
        ):
            attachments = message.Attachments
            for i in range(attachments.Count):
                attachment = attachments.Item(i + 1)
                if attachment.FileName.endswith((".csv", ".xlsx", ".xls")):
                    save_path = DOWNLOAD_DIR / attachment.FileName

                    # Add timestamp if file already exists
                    if save_path.exists():
                        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        save_path = save_path.with_name(f"{save_path.stem}_{timestamp}{save_path.suffix}")

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
        output_dir = OUTPUT_EMAIL_DIR
    elif mode == "folder":
        files = list(INPUT_DIR.glob("*.csv")) + list(INPUT_DIR.glob("*.xlsx")) + list(INPUT_DIR.glob("*.xls"))
        if not files:
            print(f"No files found in folder: {INPUT_DIR}")
            return
        output_dir = OUTPUT_FOLDER_DIR
    else:
        print("Invalid mode. Use 'email' or 'folder'.")
        return

    for file_path in files:
        clean_file_dates(file_path, output_dir)

if __name__ == "__main__":
    # Choose: "email" or "folder"
    main(mode="email")