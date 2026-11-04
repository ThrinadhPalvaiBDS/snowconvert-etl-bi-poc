"""Thin Power BI REST client (service principal via MSAL) shared by cutover + parity scripts."""
import os
import time

import msal
import requests

API = "https://api.powerbi.com/v1.0/myorg"
SCOPE = ["https://analysis.windows.net/powerbi/api/.default"]


class PowerBIClient:
    def __init__(self, tenant_id, client_id, client_secret):
        self._app = msal.ConfidentialClientApplication(
            client_id, authority=f"https://login.microsoftonline.com/{tenant_id}",
            client_credential=client_secret)
        self._token, self._exp = None, 0
        self.s = requests.Session()

    @classmethod
    def from_config(cls, cfg):
        return cls(os.environ[cfg["tenant_id_env"]], os.environ[cfg["client_id_env"]],
                   os.environ[cfg["client_secret_env"]])

    def _headers(self):
        if time.time() > self._exp - 120:
            res = self._app.acquire_token_for_client(scopes=SCOPE)
            if "access_token" not in res:
                raise RuntimeError(f"Token error: {res.get('error_description')}")
            self._token, self._exp = res["access_token"], time.time() + res.get("expires_in", 3600)
        return {"Authorization": f"Bearer {self._token}"}

    def request(self, method, path, retries=5, **kw):
        url = path if path.startswith("http") else f"{API}{path}"
        for attempt in range(retries):
            r = self.s.request(method, url, headers={**self._headers(), **kw.pop("headers", {})}, **kw)
            if r.status_code == 429 or r.status_code >= 500:
                wait = int(r.headers.get("Retry-After", 2 ** attempt * 5))
                time.sleep(wait)
                continue
            if not r.ok:
                raise RuntimeError(f"{method} {url} -> {r.status_code}: {r.text[:500]}")
            return r.json() if r.content and "json" in r.headers.get("Content-Type", "") else None
        raise RuntimeError(f"{method} {url} failed after {retries} retries")

    # ---- imports ----
    def import_pbix(self, group_id, pbix_path, display_name):
        with open(pbix_path, "rb") as fh:
            res = self.request("POST", f"/groups/{group_id}/imports",
                               params={"datasetDisplayName": display_name,
                                       "nameConflict": "CreateOrOverwrite"},
                               files={"file": (os.path.basename(pbix_path), fh)})
        import_id = res["id"]
        while True:
            st = self.request("GET", f"/groups/{group_id}/imports/{import_id}")
            if st["importState"] == "Succeeded":
                return st
            if st["importState"] == "Failed":
                raise RuntimeError(f"Import failed: {st}")
            time.sleep(5)

    # ---- datasets ----
    def take_over(self, g, d):
        self.request("POST", f"/groups/{g}/datasets/{d}/Default.TakeOver")

    def get_parameters(self, g, d):
        return self.request("GET", f"/groups/{g}/datasets/{d}/parameters")["value"]

    def update_parameters(self, g, d, params: dict):
        body = {"updateDetails": [{"name": k, "newValue": v} for k, v in params.items()]}
        self.request("POST", f"/groups/{g}/datasets/{d}/Default.UpdateParameters", json=body)

    def get_datasources(self, g, d):
        return self.request("GET", f"/groups/{g}/datasets/{d}/datasources")["value"]

    def set_basic_credentials(self, gateway_id, datasource_id, username, password):
        import json
        body = {"credentialDetails": {
            "credentialType": "Basic",
            "credentials": json.dumps({"credentialData": [
                {"name": "username", "value": username}, {"name": "password", "value": password}]}),
            "encryptedConnection": "Encrypted",
            "encryptionAlgorithm": "None",          # allowed for cloud data sources
            "privacyLevel": "Organizational"}}
        self.request("PATCH", f"/gateways/{gateway_id}/datasources/{datasource_id}", json=body)

    def refresh(self, g, d, wait=True, timeout_s=3600):
        self.request("POST", f"/groups/{g}/datasets/{d}/refreshes", json={"notifyOption": "NoNotification"})
        if not wait:
            return None
        start = time.time()
        while time.time() - start < timeout_s:
            time.sleep(15)
            last = self.request("GET", f"/groups/{g}/datasets/{d}/refreshes", params={"$top": 1})["value"][0]
            if last["status"] in ("Completed", "Failed", "Disabled", "Cancelled"):
                return last
        raise TimeoutError("refresh did not finish in time")

    def execute_dax(self, dataset_id, dax):
        body = {"queries": [{"query": dax}], "serializerSettings": {"includeNulls": True}}
        res = self.request("POST", f"/datasets/{dataset_id}/executeQueries", json=body)
        return res["results"][0]["tables"][0].get("rows", [])
