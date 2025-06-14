# %%
import os
import re
from glob import glob
import QC_flywheel
import pandas as pd

base_dir = '/Users/xiaoqianxiao/projects'
project_name = 'IFOCUS'
flywheel_client_ID = 'uw-chn.flywheel.io:djEiLeP_pwqp2Pe0Jimpi5GhRV3wAIp36HEvqdi_AnSJtgprOxhuW5Qvg'

# %%
fw = QC_flywheel.Client(flywheel_client_ID)
project = fw.projects.find_one('group=fang-lab,label=IFOCUS')
sessions = project.sessions()
output_dir = os.path.join(base_dir, project_name, 'QC')
os.makedirs(output_dir, exist_ok=True)  # Create output directory if it doesn't exist
file_of_interest = 'mriqc_'
qc_dict = {}
#%%
# Locate MRIQC files
for s in sessions:
    sub_name = f"sub-{s.subject.code}"
    acquisitions = s.acquisitions()
    ses_name = s.label
    for acq in acquisitions:
        scan_name = acq.label
        timestamp = acq.timestamp
        readable_time = timestamp.strftime('%Y-%m-%d-%H:%M:%S-%Z')
        target_file_name = f"{sub_name}_{ses_name}_{scan_name}_{readable_time}"
        for file in acq.files:
            if 'gear_info' in file.keys() and file.gear_info is not None:
                gear_name = file.gear_info.name
                print(f"Found gear: {gear_name}")
                if gear_name == 'mriqc':
                    #print(file)
                    qc_dict[target_file_name] = file

# %%
# Download files from qc_list
# if qc_dict:
#     for target_name, fw_file in qc_dict.items():
#         # skip any non-HTML files
#         if not fw_file.name.lower().endswith('.html'):
#             print(f"Skipping: {fw_file.name}")
#             continue
#
#         # ensure our saved filename also ends in .html
#         filename = target_name
#         if not filename.lower().endswith('.html'):
#             filename = f"{filename}.html"
#
#         output_path = os.path.join(output_dir, filename)
#         if os.path.exists(output_path):
#             print(f"Already exists: {output_path}")
#         else:
#             print(f"Downloading {fw_file.name} → {output_path}")
#             fw_file.download(output_path)

#%%
import os
import zipfile
import tempfile

if qc_dict:
    for target_name, fw_file in qc_dict.items():
        name = fw_file.name.lower()

        # Case 1: Direct .html file
        if name.endswith('.html'):
            filename = target_name if target_name.lower().endswith('.html') else f"{target_name}.html"
            output_path = os.path.join(output_dir, filename)

            if os.path.exists(output_path):
                print(f"Already exists: {output_path}")
            else:
                print(f"Downloading {fw_file.name} → {output_path}")
                fw_file.download(output_path)

        # Case 2: .zip file containing index.html
        elif name.endswith('.zip'):
            print(f"Processing ZIP: {fw_file.name}")

            # Save zip to a temporary file
            with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp_zip_file:
                tmp_zip_path = tmp_zip_file.name
                fw_file.download(tmp_zip_path)

            try:
                with zipfile.ZipFile(tmp_zip_path, 'r') as zf:
                    index_html = next((f for f in zf.namelist() if f.endswith('index.html')), None)

                    if index_html:
                        filename = target_name if target_name.lower().endswith('.html') else f"{target_name}.html"
                        output_path = os.path.join(output_dir, filename)

                        if os.path.exists(output_path):
                            print(f"Already exists: {output_path}")
                        else:
                            print(f"Extracting {index_html} → {output_path}")
                            with zf.open(index_html) as source, open(output_path, 'wb') as target:
                                target.write(source.read())
                    else:
                        print(f"No index.html found in {fw_file.name}")

            finally:
                os.remove(tmp_zip_path)  # Clean up the temp file

        else:
            print(f"Skipping (unsupported file type): {fw_file.name}")

