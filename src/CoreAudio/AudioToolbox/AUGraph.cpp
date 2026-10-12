#include "../AudioTrace.h"
/*
This file is part of Darling.

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/
#include "AUGraph.h"
#include <AudioToolbox/AudioComponent.h>
#include <AudioToolbox/AudioOutputUnit.h>
#include <algorithm>
#include <mutex>
#include <vector>

// An AUGraph is a set of nodes (audio units created from component descriptions), connections
// between them and render callbacks feeding their inputs. Connections and callbacks are recorded
// while the graph is edited and applied to the audio units when the graph is initialized.

namespace
{
struct Node
{
	AUNode id;
	AudioComponentDescription description;
	AudioUnit unit = nullptr;
};
}

struct AUGraphData
{
	std::recursive_mutex mutex;
	std::vector<Node> nodes;
	std::vector<AUNodeConnection> connections;
	std::vector<AUNodeRenderCallback> callbacks;
	AUNode nextNode = 1;
	bool open = false;
	bool initialized = false;
	bool running = false;
};

namespace
{
Node* findNode(AUGraphData* graph, AUNode id)
{
	for (Node& node : graph->nodes)
	{
		if (node.id == id)
			return &node;
	}
	return nullptr;
}

bool isOutputNode(const Node& node)
{
	return node.description.componentType == kAudioUnitType_Output;
}

// Undoes whatever initialization has done to the units, keeping the nodes
void uninitializeUnits(AUGraphData* graph)
{
	for (Node& node : graph->nodes)
	{
		if (node.unit)
			AudioUnitUninitialize(node.unit);
	}
	graph->initialized = false;
}
}

static OSStatus AUGraphOpenImpl(AUGraph inGraph);
static OSStatus AUGraphConnectNodeInputImpl(AUGraph inGraph, AUNode inSourceNode, UInt32 inSourceOutputNumber, AUNode inDestNode, UInt32 inDestInputNumber);
static OSStatus AUGraphSetNodeInputCallbackImpl(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber, const AURenderCallbackStruct* inInputCallback);
static OSStatus AUGraphInitializeImpl(AUGraph inGraph);
static OSStatus AUGraphStartImpl(AUGraph inGraph);
OSStatus NewAUGraph(AUGraph* outGraph)
{
    rclolAudioTrace("NEW_GRAPH\n");
	if (!outGraph)
		return kAudio_ParamError;

	*outGraph = new AUGraphData;
	return noErr;
}

OSStatus DisposeAUGraph(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	AUGraphStop(inGraph);
	AUGraphUninitialize(inGraph);
	AUGraphClose(inGraph);
	delete inGraph;
	return noErr;
}

OSStatus AUGraphAddNode(AUGraph inGraph, const AudioComponentDescription* inDescription, AUNode* outNode)
{
    if(inDescription) rclolAudioTrace("ADD_NODE type=%08x subtype=%08x\n",inDescription->componentType,inDescription->componentSubType);
	if (!inGraph || !inDescription || !outNode)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);

	Node node;
	node.id = inGraph->nextNode;
	node.description = *inDescription;

	if (inGraph->open)
	{
		// A node added to an open graph gets its unit right away
		AudioComponent component = AudioComponentFindNext(nullptr, inDescription);
		OSStatus status = component ? AudioComponentInstanceNew(component, &node.unit)
            : kAudioUnitErr_InvalidProperty;
		rclolAudioTrace("GRAPH_NODE_UNIT subtype=%08x unit=%p status=%d\n", (unsigned) node.description.componentSubType, (void*) node.unit, (int) status);
		if (status != noErr)
			return status;
	}

	inGraph->nextNode++;
	inGraph->nodes.push_back(node);
	*outNode = node.id;
	return noErr;
}

OSStatus AUGraphRemoveNode(AUGraph inGraph, AUNode inNode)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);

	auto node = std::find_if(inGraph->nodes.begin(), inGraph->nodes.end(), [&](const Node& n) { return n.id == inNode; });
	if (node == inGraph->nodes.end())
		return kAudioUnitErr_InvalidProperty;

	if (node->unit)
	{
		AudioUnitUninitialize(node->unit);
		AudioComponentInstanceDispose(node->unit);
	}
	inGraph->nodes.erase(node);

	inGraph->connections.erase(std::remove_if(inGraph->connections.begin(), inGraph->connections.end(),
		[&](const AUNodeConnection& c) { return c.sourceNode == inNode || c.destNode == inNode; }), inGraph->connections.end());
	inGraph->callbacks.erase(std::remove_if(inGraph->callbacks.begin(), inGraph->callbacks.end(),
		[&](const AUNodeRenderCallback& c) { return c.destNode == inNode; }), inGraph->callbacks.end());
	return noErr;
}

OSStatus AUGraphGetNodeCount(AUGraph inGraph, UInt32* outNumberOfNodes)
{
	if (!inGraph || !outNumberOfNodes)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	*outNumberOfNodes = (UInt32) inGraph->nodes.size();
	return noErr;
}

OSStatus AUGraphGetIndNode(AUGraph inGraph, UInt32 inIndex, AUNode* outNode)
{
	if (!inGraph || !outNode)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (inIndex >= inGraph->nodes.size())
		return kAudio_ParamError;

	*outNode = inGraph->nodes[inIndex].id;
	return noErr;
}

OSStatus AUGraphNodeInfo(AUGraph inGraph, AUNode inNode, AudioComponentDescription* outDescription, AudioUnit* outAudioUnit)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);

	Node* node = findNode(inGraph, inNode);
	if (!node)
		return kAudioUnitErr_InvalidProperty;

	if (outDescription)
		*outDescription = node->description;
	if (outAudioUnit)
	{
		// The unit only exists while the graph is open
		if (!node->unit)
			return kAudioUnitErr_Uninitialized;
		*outAudioUnit = node->unit;
	}
	return noErr;
}

static OSStatus AUGraphOpenImpl(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (inGraph->open)
		return noErr;

	for (Node& node : inGraph->nodes)
	{
		AudioComponent component = AudioComponentFindNext(nullptr, &node.description);
		OSStatus status = component ? AudioComponentInstanceNew(component, &node.unit)
            : kAudioUnitErr_InvalidProperty;
		rclolAudioTrace("GRAPH_NODE_UNIT subtype=%08x unit=%p status=%d\n", (unsigned) node.description.componentSubType, (void*) node.unit, (int) status);
		if (status != noErr)
		{
			for (Node& created : inGraph->nodes)
			{
				if (created.unit)
				{
					AudioComponentInstanceDispose(created.unit);
					created.unit = nullptr;
				}
			}
			return status;
		}
	}

	inGraph->open = true;
	return noErr;
}

OSStatus AUGraphClose(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (inGraph->running)
		AUGraphStop(inGraph);
	if (inGraph->initialized)
		uninitializeUnits(inGraph);

	for (Node& node : inGraph->nodes)
	{
		if (node.unit)
		{
			AudioComponentInstanceDispose(node.unit);
			node.unit = nullptr;
		}
	}
	inGraph->open = false;
	return noErr;
}

static OSStatus AUGraphConnectNodeInputImpl(AUGraph inGraph, AUNode inSourceNode, UInt32 inSourceOutputNumber, AUNode inDestNode, UInt32 inDestInputNumber)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (!findNode(inGraph, inSourceNode) || !findNode(inGraph, inDestNode))
		return kAudioUnitErr_InvalidProperty;

	// An input is fed by one source: a new connection or callback replaces the previous one
	AUGraphDisconnectNodeInput(inGraph, inDestNode, inDestInputNumber);

	AUNodeConnection connection;
	connection.sourceNode = inSourceNode;
	connection.sourceOutputNumber = inSourceOutputNumber;
	connection.destNode = inDestNode;
	connection.destInputNumber = inDestInputNumber;
	inGraph->connections.push_back(connection);
	return noErr;
}

OSStatus AUGraphDisconnectNodeInput(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	inGraph->connections.erase(std::remove_if(inGraph->connections.begin(), inGraph->connections.end(),
		[&](const AUNodeConnection& c) { return c.destNode == inDestNode && c.destInputNumber == inDestInputNumber; }), inGraph->connections.end());
	inGraph->callbacks.erase(std::remove_if(inGraph->callbacks.begin(), inGraph->callbacks.end(),
		[&](const AUNodeRenderCallback& c) { return c.destNode == inDestNode && c.destInputNumber == inDestInputNumber; }), inGraph->callbacks.end());
	return noErr;
}

OSStatus AUGraphClearConnections(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	inGraph->connections.clear();
	inGraph->callbacks.clear();
	return noErr;
}

static OSStatus AUGraphSetNodeInputCallbackImpl(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber, const AURenderCallbackStruct* inInputCallback)
{
	if (!inGraph || !inInputCallback)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (!findNode(inGraph, inDestNode))
		return kAudioUnitErr_InvalidProperty;

	AUGraphDisconnectNodeInput(inGraph, inDestNode, inDestInputNumber);

	AUNodeRenderCallback callback;
	callback.destNode = inDestNode;
	callback.destInputNumber = inDestInputNumber;
	callback.cback = *inInputCallback;
	inGraph->callbacks.push_back(callback);
	return noErr;
}

OSStatus AUGraphGetNumberOfInteractions(AUGraph inGraph, UInt32* outNumInteractions)
{
	if (!inGraph || !outNumInteractions)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	*outNumInteractions = (UInt32) (inGraph->connections.size() + inGraph->callbacks.size());
	return noErr;
}

OSStatus AUGraphGetInteractionInfo(AUGraph inGraph, UInt32 inInteractionIndex, AUNodeInteraction* outInteraction)
{
	if (!inGraph || !outInteraction)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);

	if (inInteractionIndex < inGraph->connections.size())
	{
		outInteraction->nodeInteractionType = 1; // kAUNodeInteraction_Connection
		outInteraction->nodeInteraction.connection = inGraph->connections[inInteractionIndex];
		return noErr;
	}

	inInteractionIndex -= (UInt32) inGraph->connections.size();
	if (inInteractionIndex < inGraph->callbacks.size())
	{
		outInteraction->nodeInteractionType = 2; // kAUNodeInteraction_InputCallback
		outInteraction->nodeInteraction.inputCallback = inGraph->callbacks[inInteractionIndex];
		return noErr;
	}
	return kAudio_ParamError;
}

static OSStatus AUGraphInitializeImpl(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (!inGraph->open)
		return kAudioUnitErr_Uninitialized;
	if (inGraph->initialized)
		return noErr;

	for (const AUNodeConnection& connection : inGraph->connections)
	{
		Node* source = findNode(inGraph, connection.sourceNode);
		Node* dest = findNode(inGraph, connection.destNode);
		if (!source || !dest)
			return kAudioUnitErr_InvalidProperty;

		AudioUnitConnection unitConnection;
		unitConnection.sourceAudioUnit = source->unit;
		unitConnection.sourceOutputNumber = connection.sourceOutputNumber;
		unitConnection.destInputNumber = connection.destInputNumber;

		OSStatus status = AudioUnitSetProperty(dest->unit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input,
			connection.destInputNumber, &unitConnection, sizeof(unitConnection));
		if (status != noErr)
			return status;
	}

	for (const AUNodeRenderCallback& callback : inGraph->callbacks)
	{
		Node* dest = findNode(inGraph, callback.destNode);
		if (!dest)
			return kAudioUnitErr_InvalidProperty;

		OSStatus status = AudioUnitSetProperty(dest->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
			callback.destInputNumber, &callback.cback, sizeof(callback.cback));
		if (status != noErr)
			return status;
	}

	for (Node& node : inGraph->nodes)
	{
		OSStatus status = AudioUnitInitialize(node.unit);
		if (status != noErr)
		{
			uninitializeUnits(inGraph);
			return status;
		}
	}

	inGraph->initialized = true;
	return noErr;
}

OSStatus AUGraphUninitialize(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (inGraph->running)
        AUGraphStop(inGraph);
    if (inGraph->initialized)
		uninitializeUnits(inGraph);
	return noErr;
}

static OSStatus AUGraphStartImpl(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (!inGraph->initialized)
		return kAudioUnitErr_Uninitialized;
	if (inGraph->running)
		return noErr;

	// Pulling starts at the output units
	for (Node& node : inGraph->nodes)
	{
		if (isOutputNode(node))
		{
			OSStatus status = AudioOutputUnitStart(node.unit);
			if (status != noErr)
				return status;
		}
	}

	inGraph->running = true;
	return noErr;
}

OSStatus AUGraphStop(AUGraph inGraph)
{
	if (!inGraph)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	if (!inGraph->running)
		return noErr;

	for (Node& node : inGraph->nodes)
	{
		if (node.unit && isOutputNode(node))
			AudioOutputUnitStop(node.unit);
	}

	inGraph->running = false;
	return noErr;
}

OSStatus AUGraphIsOpen(AUGraph inGraph, Boolean* outIsOpen)
{
	if (!inGraph || !outIsOpen)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	*outIsOpen = inGraph->open;
	return noErr;
}

OSStatus AUGraphIsInitialized(AUGraph inGraph, Boolean* outIsInitialized)
{
	if (!inGraph || !outIsInitialized)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	*outIsInitialized = inGraph->initialized;
	return noErr;
}

OSStatus AUGraphIsRunning(AUGraph inGraph, Boolean* outIsRunning)
{
	if (!inGraph || !outIsRunning)
		return kAudio_ParamError;

	std::lock_guard<std::recursive_mutex> lock(inGraph->mutex);
	*outIsRunning = inGraph->running;
	return noErr;
}

OSStatus AUGraphUpdate(AUGraph inGraph, Boolean* outIsUpdated)
{
	if (!inGraph)
		return kAudio_ParamError;

	// Edits are applied when the graph is initialized, so there is never a pending change to apply
	if (outIsUpdated)
		*outIsUpdated = true;
	return noErr;
}

OSStatus AUGraphOpen(AUGraph inGraph)
{
	OSStatus status = AUGraphOpenImpl(inGraph);
	rclolAudioTrace("GRAPH_OPEN status=%d\n", (int) status);
	return status;
}

OSStatus AUGraphConnectNodeInput(AUGraph inGraph, AUNode inSourceNode, UInt32 inSourceOutputNumber, AUNode inDestNode, UInt32 inDestInputNumber)
{
	OSStatus status = AUGraphConnectNodeInputImpl(inGraph, inSourceNode, inSourceOutputNumber, inDestNode, inDestInputNumber);
	rclolAudioTrace("GRAPH_CONNECTNODEINPUT status=%d\n", (int) status);
	return status;
}

OSStatus AUGraphSetNodeInputCallback(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber, const AURenderCallbackStruct* inInputCallback)
{
	OSStatus status = AUGraphSetNodeInputCallbackImpl(inGraph, inDestNode, inDestInputNumber, inInputCallback);
	rclolAudioTrace("GRAPH_SETNODEINPUTCALLBACK status=%d\n", (int) status);
	return status;
}

OSStatus AUGraphInitialize(AUGraph inGraph)
{
	OSStatus status = AUGraphInitializeImpl(inGraph);
	rclolAudioTrace("GRAPH_INITIALIZE status=%d\n", (int) status);
	return status;
}

OSStatus AUGraphStart(AUGraph inGraph)
{
	OSStatus status = AUGraphStartImpl(inGraph);
	rclolAudioTrace("GRAPH_START status=%d\n", (int) status);
	return status;
}
