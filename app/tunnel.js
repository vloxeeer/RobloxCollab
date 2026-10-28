const EventEmitter = require('events');

class TunnelManager extends EventEmitter {
    constructor() {
        super();
        this.tunnel = null;
        this.url = null;
    }

    async start(port) {
        const localtunnel = require('localtunnel');
        
        if (this.tunnel) {
            this.tunnel.close();
        }

        this.tunnel = await localtunnel({ port });
        this.url = this.tunnel.url;

        this.tunnel.on('close', () => {
            this.url = null;
            this.emit('closed');
        });

        this.tunnel.on('error', (err) => {
            this.emit('error', err);
        });

        return this.url;
    }

    stop() {
        if (this.tunnel) {
            this.tunnel.close();
            this.tunnel = null;
            this.url = null;
        }
    }
}

module.exports = TunnelManager;