# OTModelSyncer

## Syncs products and variants with models and items from Powersoft365, respectively

This library has dependencies from currently private repos.
To build and test it with docker run the following command. This assumes you have a private key that has access to the repos.
Run the following command to test it:

```console
foo@bar:$ docker build --build-arg GITHUB_SSH="$(cat ~/.ssh/id_ecdsa)" -f testing.Dockerfile -t otms . && docker run -t otms 
```
*Note: replace  `~/.ssh/id_ecdsa` with the location of your private key (if different)*
