#!/usr/bin/env python3

import os
import sys

import dbus
import dbus.lowlevel
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


SERVICE = "org.pipewire.Telephony"
ROOT_PATH = "/org/pipewire/Telephony"
GATEWAY_PATH = f"{ROOT_PATH}/ag1"
CALL_PATH = f"{GATEWAY_PATH}/call1"
GATEWAY_IFACE = "org.pipewire.Telephony.AudioGateway1"
TRANSPORT_IFACE = "org.pipewire.Telephony.AudioGatewayTransport1"
CALL_IFACE = "org.pipewire.Telephony.Call1"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"


def gateway_properties():
    return {
        "Address": dbus.String("AA:BB:CC:DD:EE:FF"),
        "SpeakerVolume": dbus.Byte(12),
        "MicrophoneVolume": dbus.Byte(10),
    }


def transport_properties():
    return {
        "State": dbus.String("active"),
        "Codec": dbus.Byte(2),
        "RejectSCO": dbus.Boolean(False),
    }


def call_properties():
    return {
        "LineIdentification": dbus.String("+123"),
        "IncomingLine": dbus.String("mobile"),
        "Name": dbus.String("Ada"),
        "Multiparty": dbus.Boolean(True),
        "State": dbus.String("incoming"),
    }


class Root(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, ROOT_PATH)
        self.gateway_present = True
        self.gateway = None

    @dbus.service.method(OBJECT_MANAGER, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        if not self.gateway_present:
            return {}
        interfaces = {GATEWAY_IFACE: self.gateway.gateway}
        if self.gateway.transport_present:
            interfaces[TRANSPORT_IFACE] = self.gateway.transport
        return {GATEWAY_PATH: interfaces}

    @dbus.service.signal(OBJECT_MANAGER, signature="oa{sa{sv}}")
    def InterfacesAdded(self, path, interfaces):
        pass

    @dbus.service.signal(OBJECT_MANAGER, signature="oas")
    def InterfacesRemoved(self, path, interfaces):
        pass


class Gateway(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, GATEWAY_PATH)
        self.gateway = gateway_properties()
        self.transport = transport_properties()
        self.call = call_properties()
        self.call_present = True
        self.transport_present = True

    @dbus.service.method(OBJECT_MANAGER, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        if not self.call_present:
            return {}
        return {CALL_PATH: {CALL_IFACE: self.call}}

    @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {
            GATEWAY_IFACE: self.gateway,
            TRANSPORT_IFACE: self.transport,
        }.get(str(interface), {})

    @dbus.service.signal(OBJECT_MANAGER, signature="oa{sa{sv}}")
    def InterfacesAdded(self, path, interfaces):
        pass

    @dbus.service.signal(OBJECT_MANAGER, signature="oas")
    def InterfacesRemoved(self, path, interfaces):
        pass

    @dbus.service.signal(PROPERTIES, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class Call(dbus.service.Object):
    def __init__(self, bus, gateway):
        super().__init__(bus, CALL_PATH)
        self.gateway = gateway

    @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.gateway.call if str(interface) == CALL_IFACE else {}

    @dbus.service.signal(PROPERTIES, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class Simulator:
    def __init__(self):
        address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        self.bus = dbus.bus.BusConnection(address)
        self.name = dbus.service.BusName(SERVICE, bus=self.bus, do_not_queue=True)
        self.root = Root(self.bus)
        self.gateway = Gateway(self.bus)
        self.root.gateway = self.gateway
        self.call = Call(self.bus, self.gateway)
        self.foreign = dbus.bus.BusConnection(address)

    def edge_properties(self):
        self.gateway.gateway.update(
            SpeakerVolume=dbus.String("wrong-type"),
            MicrophoneVolume=dbus.Byte(0),
        )
        self.gateway.PropertiesChanged(
            GATEWAY_IFACE,
            {
                "SpeakerVolume": dbus.String("wrong-type"),
                "MicrophoneVolume": dbus.Byte(0),
                "Unknown": dbus.String("ignored"),
            },
            ["SpeakerVolume", "SpeakerVolume", "Unknown"],
        )

        self.gateway.transport.update(
            State=dbus.Byte(1), Codec=dbus.Byte(255), RejectSCO=dbus.Boolean(False)
        )
        self.gateway.PropertiesChanged(
            TRANSPORT_IFACE,
            {
                "State": dbus.Byte(1),
                "Codec": dbus.Byte(255),
                "RejectSCO": dbus.Boolean(False),
            },
            ["State"],
        )

        self.gateway.call.update(
            Name=dbus.Int32(7),
            Multiparty=dbus.Boolean(False),
            State=dbus.String("future-ringing"),
        )
        self.call.PropertiesChanged(
            CALL_IFACE,
            {
                "Name": dbus.Int32(7),
                "Multiparty": dbus.Boolean(False),
                "State": dbus.String("future-ringing"),
            },
            ["Name", "Name"],
        )

    def irrelevant_signals(self):
        self.gateway.PropertiesChanged(
            "org.example.NotTelephony", {"SpeakerVolume": dbus.Byte(15)}, []
        )
        self.gateway.PropertiesChanged(
            GATEWAY_IFACE, {"Unknown": dbus.String("ignored")}, ["Unknown"]
        )
        message = dbus.lowlevel.SignalMessage(
            GATEWAY_PATH, PROPERTIES, "PropertiesChanged"
        )
        message.append(
            GATEWAY_IFACE,
            {"MicrophoneVolume": dbus.Byte(15)},
            [],
            signature="sa{sv}as",
        )
        self.foreign.send_message(message)
        self.foreign.flush()

    def malformed_then_valid(self):
        message = dbus.lowlevel.SignalMessage(
            GATEWAY_PATH, PROPERTIES, "PropertiesChanged"
        )
        message.append(GATEWAY_IFACE, signature="s")
        self.bus.send_message(message)
        self.bus.flush()
        self.gateway.gateway["MicrophoneVolume"] = dbus.Byte(3)
        self.gateway.PropertiesChanged(
            GATEWAY_IFACE, {"MicrophoneVolume": dbus.Byte(3)}, []
        )

    def remove_call_twice(self):
        self.gateway.call_present = False
        for _ in range(2):
            self.gateway.InterfacesRemoved(CALL_PATH, [CALL_IFACE])

    def add_call(self):
        self.gateway.call = {
            "LineIdentification": dbus.String(""),
            "IncomingLine": dbus.String(""),
            "Name": dbus.String(""),
            "Multiparty": dbus.Boolean(False),
            "State": dbus.String("waiting"),
        }
        self.gateway.call_present = True
        self.gateway.InterfacesAdded(CALL_PATH, {CALL_IFACE: self.gateway.call})

    def orphan_call(self):
        self.gateway.InterfacesAdded(
            f"{ROOT_PATH}/other/call9", {CALL_IFACE: call_properties()}
        )

    def remove_transport_twice(self):
        self.gateway.transport_present = False
        for _ in range(2):
            self.root.InterfacesRemoved(GATEWAY_PATH, [TRANSPORT_IFACE])

    def add_transport(self):
        self.gateway.transport = transport_properties()
        self.gateway.transport_present = True
        self.root.InterfacesAdded(
            GATEWAY_PATH, {TRANSPORT_IFACE: self.gateway.transport}
        )

    def remove_gateway_twice(self):
        self.root.gateway_present = False
        for _ in range(2):
            self.root.InterfacesRemoved(
                GATEWAY_PATH, [GATEWAY_IFACE, TRANSPORT_IFACE]
            )

    def command(self, line):
        commands = {
            "edge-properties": self.edge_properties,
            "irrelevant-signals": self.irrelevant_signals,
            "malformed-then-valid": self.malformed_then_valid,
            "remove-call-twice": self.remove_call_twice,
            "add-call": self.add_call,
            "orphan-call": self.orphan_call,
            "remove-transport-twice": self.remove_transport_twice,
            "add-transport": self.add_transport,
            "remove-gateway-twice": self.remove_gateway_twice,
        }
        if line == "quit":
            return False
        commands[line]()
        print(f"DONE {line}", flush=True)
        return True


def main():
    DBusGMainLoop(set_as_default=True)
    simulator = Simulator()
    loop = GLib.MainLoop()

    def read_command(source, _condition):
        line = source.readline()
        if not line or not simulator.command(line.strip()):
            loop.quit()
            return False
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, read_command)
    print("READY", flush=True)
    loop.run()


if __name__ == "__main__":
    main()
