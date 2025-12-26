# Sharon

`Sharon` is an automated tool that scans public GitHub repositories for leaked credentials (using trufflehog)


# Requirements

- Github cli
- [Trufflehog](https://github.com/trufflesecurity/trufflehog)
  



# Installation & Usage
```
> git clone <repo>
```
- Review the source code and set all required values according to their respective parameters 
  
```
> chmod +x sharon.sh
```
```
> sharon.sh
```



# How it Works

- Repository Cloning --> Data Restoration --> Scanning & Verification --> Notification.

> **Note**: After scanning and verification, repositories are automatically deleted to free up disk space for subsequent scans.. 

- Please refere to this write-up by [Sharon Brizinov](https://medium.com/@sharon.brizinov/how-i-made-64k-from-deleted-files-a-bug-bounty-story-c5bd3a6f5f9b) For a deeper understanding of the methodology behind this tool

---
> Scan only repositories you own or have explicit permission to test



