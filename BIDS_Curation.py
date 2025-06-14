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

#%%
gears = fw.gears()
gear_dict = {gear.gear['name']: gear.to_dict() for gear in gears}

#%%
curate_bids_gear = None
for gear in gears:
    if gear.gear['name'] == 'curate-bids':
        curate_bids_gear = gear
        break

#%%
local_template_path = '/Users/xiaoqianxiao/projects/flywheel/information/chn-reproin-extension-project-template.json'
project.upload_file(local_template_path)
files = project.files
template_file = next((f for f in files if f.name == 'chn-reproin-extension-project-template.json'), None)
if not template_file:
    raise Exception("Template file upload failed or not found!")
print(f"Template file uploaded: {template_file.name}")

#%%
# Configure the gear
gear_config = {
    'base_template': 'ReproIn',
    'intendedfor_regexes': 'fmap-.* .*_bold',
    'reset': False,
    'use_or_save_config': 'Save Config File',
    'verbosity': 'INFO'
}

inputs = {
    'template': template_file
}
#%%
# Find the specific session to test (e.g., ses-pilot)
test_session = project.sessions.find_first('label=ses-pilot')
if not test_session:
    raise Exception("Session 'ses-pilot' not found in the project!")
print(f"Testing on session: {test_session.label}")

# Run the gear on the test session
The error AttributeError: 'str' object has no attribute 'id' when trying to access job.id indicates that the job variable is a string instead of a Flywheel Job object, which should have an id attribute. This likely happens because the curate_bids_gear.run() method failed to return a proper Job object, possibly due to an issue with the API key, gear configuration, or session object. Since you’re running this in a PyCharm console and the error occurs on a standalone job.id line, let’s debug and fix the script.

Likely Causes
Invalid API Key: If 'YOUR_ACTUAL_API_KEY_HERE' wasn’t replaced with a valid key, the flywheel.Client() initialization fails, causing downstream methods to return invalid objects.
Session Not Found: The test_session might not be correctly retrieved if ses-T12 doesn’t match an existing session label.
Gear Run Failure: The run() method might have failed silently, returning a string (e.g., an error message) instead of a Job object.
Debugging Steps
Check API Key: Ensure the key is valid.
Verify Session: Confirm ses-T12 exists.
Inspect job: Add a print statement to see what job contains.
Updated Script with Debugging
Let’s add checks and print statements to diagnose the issue:

python

Collapse

Wrap

Run

Copy
import QC_flywheel
import time

# Initialize Flywheel client with your actual API key
api_key = 'YOUR_ACTUAL_API_KEY_HERE'  # Replace with your API key
fw = QC_flywheel.Client(api_key)

# Verify client initialization
print(f"Client type: {type(fw)}")
if not fw.get_current_user():
    raise Exception("API key authentication failed!")

# Retrieve all gears
gears = fw.gears()
gear_dict = {gear.gear['name']: gear.to_dict() for gear in gears}

# Find the curate-bids gear
curate_bids_gear = None
for gear in gears:
    if gear.gear['name'] == 'curate-bids':
        curate_bids_gear = gear
        break

if not curate_bids_gear:
    raise Exception("curate-bids gear not found!")

# Find the project
project = fw.projects.find_first('label=IFOCUS')
if not project:
    raise Exception("Project not found!")

# Upload the local template file
local_template_path = '/path/to/your/chn-reproin-extension-project-template.json'
project.upload_file(local_template_path)

# Verify the uploaded file
files = project.files
template_file = next((f for f in files if f.name == 'chn-reproin-extension-project-template.json'), None)
if not template_file:
    raise Exception("Template file upload failed or not found!")

# Configure the gear with intendedfor_regexes
gear_config = {
    'base_template': 'ReproIn',
    'intendedfor_regexes': 'fmap-.* .*_bold',
    'reset': False,
    'use_or_save_config': 'Save Config File',
    'verbosity': 'INFO'
}

# Set inputs with the uploaded template
inputs = {
    'template': template_file
}

# Find the specific session to test (e.g., ses-T12)
test_session = project.sessions.find_first('label=ses-T12')
if not test_session:
    raise Exception("Session 'ses-T12' not found in the project! Available sessions: {[s.label for s in project.sessions()]}")
print(f"Testing on session: {test_session.label}")
#%%
import time
# # Run the gear on the test session
# job_result = curate_bids_gear.run(
#     config=gear_config,
#     inputs=inputs,
#     destination=test_session
# )
# print(f"Job result type: {type(job_result)}")
# print(f"Job result content: {job_result}")
#
# # Handle the case where run() returns a string (job ID)
# if isinstance(job_result, str):
#     job_id = job_result
#     job = fw.get_job(job_id)
#     print(f"Retrieved job with ID: {job_id}")
# else:
#     job = job_result
#     job_id = job.id
#     print(f"Job submitted with ID: {job_id}")
#
# # Monitor the job
# while True:
#     job = fw.get_job(job_id)
#     state = job.state
#     print(f"Job state: {state}")
#     if state in ['complete', 'failed', 'cancelled']:
#         break
#     time.sleep(10)  # Wait 10 seconds before checking again
#
# if state == 'complete':
#     print("BIDS curation completed successfully on the test session!")
# else:
#     print(f"Job {state}. Check logs for details: {fw.get_job_logs(job_id)}")

#%%
# Get all sessions in the project
sessions = project.sessions()
if not sessions:
    raise Exception("No sessions found in the project!")

job_ids = []
for session in sessions:
    print(f"Submitting job for session: sub-{session.subject.label}_ses-{session.label}")
    job_result = curate_bids_gear.run(
        config=gear_config,
        inputs=inputs,
        destination=session
    )
    if isinstance(job_result, str):
        job_id = job_result
    else:
        job_id = job_result.id
    job_ids.append(job_id)
    print(f"Submitted job with ID: {job_id}")

print(f"All jobs submitted with IDs: {job_ids}")