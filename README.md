## example.com domain on Proxmox

### What?

With these scripts you can install a complete example.com domain for testing purposes on your proxmox server. This includes:

1. A client machine running a graphical MATE environment as entry point that can be accessed over RDP with the following software on it:
    - a Firefox Browser with pre-loaded certificates
    - Thunderbird Mail client, pre-loaded
2. An OpenWrt Router as exit point
3. DNS (running on dnsmasq on the OpenWrt Router) for the example.com domain
4. A Docker host (running in an unprivileged LXC Container)
5. A "fake" SMTP / IMAP Server

The environment has everything you need to run the domain, including TLS certificates and e-Mail (internal only)

### Why?

A lot of examples and samples in the internet use the "example.com" domain. Testing software and running it in a "production" environment, i.e. in your "real" network can be cumbersome, because:

- you might break something
- you jeopardize the security and/or reliability of your network
- you would have to change things and roll them back later
- in order to make the examples run in the network, you need to change a lot of config files

For all these reasons, a test environment or "Sandbox" can be extremely useful.

- apply samples as they are without too many changes (we run the example.com domain - you remember ;-) )
- No influence on the "real" world - everything is safely encapsulated
- Quick deployment of Containers or VMs into the environment - just give a machine the virtual bridge as network and it will run inside the sandbox
- The client container is lightweight, RDP makes access from Linux or Windows easy

### How? (1) - Preparation steps

Create a virtual network for your test "sandbox" that is connected nowhere (i.e. will only be visible inside the example.com). This will be the network that your example.com domain will use.

- Select the PVE Server in the Proxmox VE GUI
- Select the "Network" node
- Click on "Create" - "Linux Bridge"
- do only fill out the following fields (i.e. leave all others blank):
    - Name (e.g. "vmbr999")
    - Autostart: ticked
    - VLAN aware: ticked
    - Comment (e.g. "Virtual Sandbox Bridge")

### How? (2) - Installation

The installation can be done automatically. 
Run the following command (as root) on the PVE Server:

If you have git installed on your Proxmox Server, you can run 

```bash
git clone https://github.com/onemarcfifty/example.com-proxmox.git
```

If not, then you could download and unzip the repo by typing 

```bash
wget https://github.com/onemarcfifty/example.com-proxmox/archive/refs/heads/main.zip
unzip main.zip
```

then cd into the subfolder, review and adapt the config file and launch
```bash
./deploy-sandbox.sh
```

### More Info


