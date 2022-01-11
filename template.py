import yaml
import os
import sys
import jinja2
import subprocess


sys.stdout.write(jinja2.Template(open('mattermost-deployed-template.md').read()).render(
    basename=os.path.basename(os.getcwd()),
    oda_namespace=os.getenv('ODA_NAMESPACE', 'unknown-environment'),
    version=yaml.safe_load(open("frontend-container/version.yaml")),
    revision=dict(
        commit=subprocess.check_output(["git", "rev-parse", "HEAD"]).decode(),
        diff=subprocess.check_output(["git", "show", "HEAD"]).decode()
    )
))