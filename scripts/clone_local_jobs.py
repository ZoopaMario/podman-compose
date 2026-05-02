#!/usr/bin/env python3
import subprocess
import json
import os
import re

def run_cmd(cmd, capture=True):
    res = subprocess.run(cmd, capture_output=capture, text=True)
    if capture and res.returncode != 0:
        print(f"Error running {' '.join(cmd)}: {res.stderr}")
    return res.stdout if capture else "", res.returncode == 0

def main():
    print("Listing existing backups...")
    out, success = run_cmd(["sudo", "podman", "exec", "duplicati", "duplicati-server-util", "list-backups"])
    if not success:
        print("Failed to list backups. Are you root/sudo?")
        return

    # Extract jobs like "1: Cryptpad -> Remote"
    jobs = []
    for line in out.splitlines():
        match = re.match(r'^(\d+):\s+(.*)$', line.strip())
        if match:
            job_id, job_name = match.groups()
            if " -> Remote" in job_name and not job_name.startswith("MEDIA-"):
                jobs.append((job_id, job_name))

    if not jobs:
        print("No remote application jobs found to clone.")
        return

    for job_id, job_name in jobs:
        app_name = job_name.split(" -> Remote")[0]
        local_job_name = f"{app_name} -> Local"
        
        # Check if local job already exists
        if f": {local_job_name}" in out:
            print(f"Job '{local_job_name}' already exists. Skipping.")
            continue

        print(f"\n=========================================")
        print(f"Cloning '{job_name}' to '{local_job_name}'...")
        print(f"=========================================")
        
        # We need the user to enter the passphrase interactively
        # Note: --destination /tmp/ puts it inside the duplicati container
        cmd_export = [
            "sudo", "podman", "exec", "-it", "duplicati", "duplicati-server-util", "export", 
            job_id, "--unencrypted", "--export-passwords", "true", "--overwrite", "--destination", "/tmp/"
        ]
        
        print(f"Exporting {job_name}... PLEASE ENTER PASSPHRASE IF PROMPTED:")
        subprocess.run(cmd_export) # Interactive
        
        # Copy the exported JSON to the host so we can edit it safely with Python
        # The filename created inside the container is usually "{id}-{name}.json" but spaces might be preserved.
        # Duplicati replaces some chars, let's just find the newest json in /tmp
        
        find_cmd = ["sudo", "podman", "exec", "duplicati", "sh", "-c", "ls -t /tmp/*.json | head -n1"]
        out_find, success = run_cmd(find_cmd)
        if not success or not out_find.strip():
            print(f"Failed to find exported JSON for {job_name} inside container.")
            continue
            
        container_filepath = out_find.strip()
        host_filepath = f"/tmp/export_{job_id}.json"
        
        # Copy to host
        run_cmd(["sudo", "podman", "cp", f"duplicati:{container_filepath}", host_filepath])
        
        if not os.path.exists(host_filepath):
            print(f"Failed to copy {container_filepath} to host.")
            continue
            
        try:
            with open(host_filepath, 'r') as f:
                config = json.load(f)
        except Exception as e:
            print(f"Failed to parse JSON for {job_name}: {e}")
            continue
            
        # Modify the configuration
        config["Backup"]["Name"] = local_job_name
        config["Backup"]["ID"] = None
        config["Backup"]["DBPath"] = None
        config["Backup"]["Metadata"] = {}
        
        safe_app_name = app_name.lower().replace(" ", "")
        config["Backup"]["TargetURL"] = f"file:///mnt/backup/{safe_app_name}"
        
        # Write modified JSON back
        with open(host_filepath, 'w') as f:
            json.dump(config, f, indent=2)
            
        # Copy back to container
        run_cmd(["sudo", "podman", "cp", host_filepath, f"duplicati:{container_filepath}"])
        
        # Import the new job
        print(f"Importing '{local_job_name}' into Duplicati...")
        import_cmd = ["sudo", "podman", "exec", "duplicati", "duplicati-server-util", "import", container_filepath, ""]
        import_out, import_success = run_cmd(import_cmd)
        
        if import_success:
            print(f"Successfully created '{local_job_name}'.")
        else:
            print(f"Failed to import '{local_job_name}': {import_out}")
            
        # Cleanup
        run_cmd(["sudo", "podman", "exec", "duplicati", "rm", "-f", container_filepath])
        os.remove(host_filepath)

    print("\nAll missing local backup jobs have been cloned successfully.")

if __name__ == "__main__":
    main()
