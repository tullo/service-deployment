# CI

https://dev.to/stack-labs/manage-your-secrets-in-git-with-sops-gitlab-ci-2jnd

## Import public key of CI

Each team member should import the public CI key

`gpg --import ci.public.key`

## Update keys of every secret

`CI` is a new team member. Let CI access and decrypt every secret.

So we will use the sops updatekeys `secret` on every secret.

```sh
# add CI fingerprint to relevant sections, files, etc
nano .sops.yaml
# sops updatekeys <secret> on every secret
sops updatekeys .enc.env-db
```

## GitLab CI Configuration

Now, the CI is ready to be configured.

Add the KEY anf  PASSPHRASE to the settings of the CI system.

Then, define a GitLab CI job able to read the value from the encrypted secret.

```yaml
deploy int:
  image: google/cloud-sdk # <1>
  before_script:
  - apt-get update && apt-get install -y curl gnupg # <2>
  - curl -qsL https://github.com/mozilla/sops/releases/download/v3.5.0/sops-v3.5.0.linux -o /usr/local/bin/sops # <3>
  - chmod +x /usr/local/bin/sops
  - cat $KEY | gpg --batch --import # <4> 
  - echo $PASSPHRASE | gpg --batch --always-trust --yes --passphrase-fd 0 --pinentry-mode=loopback -s $(mktemp) # <5>
  script:
  - sops -d int.encrypted.env > int.env # <6>
  - cat int.env
```

https://gitlab.com/davinkevin/sops-blog-post-repository/-/jobs/584226660

The recipe above is heavy as it has to download and install files every time the job runs.

Let's reduce the friction and add the tooling to a docker image:

> Dockerfile:

```docker
FROM tutum/curl AS downloader

RUN curl -qsL https://github.com/mozilla/sops/releases/download/v3.5.0/sops-v3.5.0.linux -o /opt/sops && \
    chmod +x /opt/sops

FROM google/cloud-sdk as final

COPY --from=downloader /opt/sops /usr/local/bin/sops

RUN apt-get update && apt-get install -y gnupg --no-install-recommends
```

Use the resulting image in the gitlab job:

> .gitlab-ci.yml

```yaml
deploy int:
  image: registry.gitlab.com/davinkevin/sops-blog-post-repository/gcloud-sops # Image created by the previous Dockerfile 🐳
  before_script:
  - cat $KEY | gpg --batch --import
  - echo $PASSPHRASE | gpg --batch --always-trust --yes --passphrase-fd 0 --pinentry-mode=loopback -s $(mktemp)
  script:
  - sops -d int.encrypted.env > int.env
  - cat int.env
```

Extract gpg key authorization into a function for reuse:

```yaml
# a YAML anchor used to set a custom shell function and calling it right away.
.auth: &auth |
  function gpg_auth() {
    cat $KEY | gpg --batch --import > /dev/null
    echo $PASSPHRASE | gpg --batch --always-trust --yes --passphrase-fd 0 --pinentry-mode=loopback -s $(mktemp) > /dev/null
  }

  gpg_auth

deploy alice:
  image: registry.gitlab.com/davinkevin/sops-blog-post-repository/gcloud-sops
  before_script:
  - *auth # Usage of the anchor as a before_script step in the job.
  script: 
  - sops -d dev_a.encrypted.env > dev_a.env
  - cat dev_a.env

deploy int:
  image: registry.gitlab.com/davinkevin/sops-blog-post-repository/gcloud-sops
  before_script:
  - *auth # Usage of the anchor as a before_script step in the job.
  script: 
  - sops -d int.encrypted.env > int.env
  - cat int.env
```

Of course, this is just an extract of the real .gitlab-ci.yaml, which includes linting, test, build & CI 👍.

https://gitlab.com/davinkevin/sops-blog-post-repository

SOPS decrypt and deploy a kubernetes secret:

```yaml
deploy int:
  image: registry.gitlab.com/davinkevin/sops-blog-post-repository/gcloud-sops
  before_script:
  - *auth # Usage of the anchor as a before_script step in the job.
  script: # decrypt the k8s secret and deploy
  - sops -d app-secret.yaml | kubectl apply -f -
```

https://dev.to/stack-labs/manage-your-secrets-in-git-with-sops-for-kubernetes-57me

https://gitlab.com/davinkevin/sops-blog-post

https://dev.to/stack-labs/manage-your-secrets-in-git-with-sops-for-kubectl-kustomize-45b5
