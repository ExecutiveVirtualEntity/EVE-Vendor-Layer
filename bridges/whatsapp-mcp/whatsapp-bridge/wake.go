package main

// Wake-hook: when a WhatsApp message arrives that matches the allowlist + filter
// rules, POST a wake prompt to the SharedBrain server's /wake endpoint so Eve
// (Claude Code in the persistent PTY) sees it and responds.
//
// Triggered from handleMessage (in a goroutine) so it never blocks the
// whatsmeow event loop. Reads its config from wake-config.json next to the
// bridge binary; if the file is missing or enabled=false, the hook is a no-op
// and the bridge behaves exactly like upstream lharries/whatsapp-mcp.

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	waProto "go.mau.fi/whatsmeow/binary/proto"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

type WakeConfig struct {
	Enabled              bool     `json:"enabled"`
	WakeURL              string   `json:"wake_url"`
	SecretToken          string   `json:"secret_token"`
	AllowedSenderNumbers []string `json:"allowed_sender_numbers"`
	GroupTriggerPrefixes []string `json:"group_trigger_prefixes"`
	AlwaysWakeOnDM       bool     `json:"always_wake_on_dm"`
	WhisperPython        string   `json:"whisper_python"`
	WhisperScript        string   `json:"whisper_script"`
	WhisperModel         string   `json:"whisper_model"`
	GeminiAPIKeyEnv      string   `json:"gemini_api_key_env"`
	GeminiAPIKeyFile     string   `json:"gemini_api_key_file"`
	GeminiModel          string   `json:"gemini_model"`
	Source               string   `json:"source"`
	MaxMediaWaitSec      int      `json:"max_media_wait_sec"`
}

var wakeConfig *WakeConfig

func loadWakeConfig() {
	path := "wake-config.json"
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Printf("[wake] no wake-config.json — wake-hook disabled (%v)\n", err)
		return
	}
	var cfg WakeConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		fmt.Printf("[wake] failed to parse wake-config.json: %v — wake-hook disabled\n", err)
		return
	}
	if !cfg.Enabled {
		fmt.Println("[wake] wake-config.json present but enabled=false — wake-hook disabled")
		return
	}
	if cfg.MaxMediaWaitSec == 0 {
		cfg.MaxMediaWaitSec = 90
	}
	if cfg.WhisperModel == "" {
		cfg.WhisperModel = "small"
	}
	if cfg.GeminiModel == "" {
		cfg.GeminiModel = "gemini-2.0-flash"
	}
	if cfg.Source == "" {
		cfg.Source = "whatsapp_bridge"
	}
	wakeConfig = &cfg
	fmt.Printf("[wake] enabled, wake_url=%s, %d allowed senders\n",
		cfg.WakeURL, len(cfg.AllowedSenderNumbers))
}

// MaybeWakeOnMessage — call from handleMessage in a goroutine.
func MaybeWakeOnMessage(client *whatsmeow.Client, store *MessageStore, msg *events.Message, logger waLog.Logger) {
	if wakeConfig == nil {
		return
	}
	if msg.Info.IsFromMe {
		return
	}

	senderNumber := msg.Info.Sender.User
	allowed := contains(wakeConfig.AllowedSenderNumbers, senderNumber)
	// If the direct match fails and the sender is a LID (or vice versa), ask
	// whatsmeow's device store for the paired JID and retry the allowlist check.
	// Allows the allowlist to stay keyed on phone numbers even after WhatsApp
	// migrates a contact onto the Linked-ID privacy system.
	if !allowed {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		altJID, err := client.Store.GetAltJID(ctx, msg.Info.Sender)
		cancel()
		if err == nil && !altJID.IsEmpty() && contains(wakeConfig.AllowedSenderNumbers, altJID.User) {
			logger.Infof("[wake] resolved %s -> %s via LID map — allowed",
				msg.Info.Sender.String(), altJID.String())
			allowed = true
		} else if err != nil {
			logger.Warnf("[wake] GetAltJID failed for %s: %v", msg.Info.Sender.String(), err)
		}
	}
	if !allowed {
		logger.Infof("[wake] sender %s not in allowlist — dropping", senderNumber)
		return
	}

	isGroup := msg.Info.Chat.Server == "g.us"
	text := extractTextOrCaption(msg.Message)
	mentionedJIDs, quotedParticipant := extractContextInfo(msg.Message)

	myNumber := ""
	if client.Store.ID != nil {
		myNumber = client.Store.ID.User
	}

	if isGroup {
		addressed := false
		for _, j := range mentionedJIDs {
			if myNumber != "" && strings.HasPrefix(j, myNumber+"@") {
				addressed = true
				break
			}
		}
		if !addressed && quotedParticipant != "" && myNumber != "" &&
			strings.HasPrefix(quotedParticipant, myNumber+"@") {
			addressed = true
		}
		if !addressed {
			lower := strings.ToLower(strings.TrimSpace(text))
			for _, prefix := range wakeConfig.GroupTriggerPrefixes {
				if strings.HasPrefix(lower, strings.ToLower(prefix)) {
					addressed = true
					break
				}
			}
		}
		if !addressed {
			logger.Infof("[wake] group message in %s not addressed to Eve — dropping",
				msg.Info.Chat.String())
			return
		}
	} else {
		if !wakeConfig.AlwaysWakeOnDM {
			return
		}
	}

	mediaContext := ""
	mediaType, _, _, _, _, _, _ := extractMediaInfo(msg.Message)
	if mediaType != "" {
		mediaContext = processIncomingMedia(client, store, msg, mediaType, logger)
	}

	senderName := senderNumber
	if contact, err := client.Store.Contacts.GetContact(context.Background(), msg.Info.Sender); err == nil {
		if contact.FullName != "" {
			senderName = contact.FullName
		} else if contact.PushName != "" {
			senderName = contact.PushName
		}
	}

	chatJID := msg.Info.Chat.String()
	chatName := chatJID
	var n string
	if err := store.db.QueryRow("SELECT name FROM chats WHERE jid = ?", chatJID).Scan(&n); err == nil && n != "" {
		chatName = n
	}

	textForPrompt := text
	if textForPrompt == "" && mediaType != "" {
		textForPrompt = fmt.Sprintf("(no text — %s only)", mediaType)
	}

	var prompt string
	if isGroup {
		prompt = fmt.Sprintf(
			`Eve, %s sent a WhatsApp message in group "%s" (chat JID: %s): %q. %sThe bridge has already marked the message as read (blue ✓✓), so do NOT send a 🧠 receipt — the blue check is the receipt. Check the latest message in that chat and reply appropriately in the same group.`,
			senderName, chatName, chatJID, textForPrompt, mediaContext)
	} else {
		prompt = fmt.Sprintf(
			`Eve, %s sent you a WhatsApp DM (chat JID: %s): %q. %sThe bridge has already marked the message as read (blue ✓✓), so do NOT send a 🧠 receipt — the blue check is the receipt. Check the latest message and reply appropriately in the same DM.`,
			senderName, chatJID, textForPrompt, mediaContext)
	}

	body := map[string]string{
		"token":  wakeConfig.SecretToken,
		"prompt": prompt,
		"source": wakeConfig.Source,
	}
	bodyBytes, _ := json.Marshal(body)

	httpClient := &http.Client{Timeout: 10 * time.Second}
	resp, err := httpClient.Post(wakeConfig.WakeURL, "application/json", bytes.NewReader(bodyBytes))
	if err != nil {
		logger.Warnf("[wake] POST %s failed: %v", wakeConfig.WakeURL, err)
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	logger.Infof("[wake] fired (status=%d): %s", resp.StatusCode, string(respBody))

	// Only mark read (blue ✓✓) if the wake hook accepted the message — that's
	// the moment we know Eve is actually alive to process it. If SharedBrain
	// is down or returns non-2xx, no blue check appears, which matches the
	// semantic Alex asked for: "blue check = Eve really got it."
	if resp.StatusCode >= 200 && resp.StatusCode < 300 && msg.Info.ID != "" {
		if err := client.MarkRead(
			context.Background(),
			[]types.MessageID{msg.Info.ID},
			time.Now(),
			msg.Info.Chat,
			msg.Info.Sender,
		); err != nil {
			logger.Warnf("[wake] MarkRead failed for %s: %v", msg.Info.ID, err)
		}
	}
}

func extractTextOrCaption(msg *waProto.Message) string {
	if msg == nil {
		return ""
	}
	if t := extractTextContent(msg); t != "" {
		return t
	}
	if img := msg.GetImageMessage(); img != nil && img.GetCaption() != "" {
		return img.GetCaption()
	}
	if vid := msg.GetVideoMessage(); vid != nil && vid.GetCaption() != "" {
		return vid.GetCaption()
	}
	if doc := msg.GetDocumentMessage(); doc != nil && doc.GetCaption() != "" {
		return doc.GetCaption()
	}
	return ""
}

func extractContextInfo(msg *waProto.Message) (mentionedJIDs []string, quotedParticipant string) {
	if msg == nil {
		return nil, ""
	}
	if ext := msg.GetExtendedTextMessage(); ext != nil {
		if ctx := ext.GetContextInfo(); ctx != nil {
			return ctx.GetMentionedJID(), ctx.GetParticipant()
		}
	}
	if img := msg.GetImageMessage(); img != nil {
		if ctx := img.GetContextInfo(); ctx != nil {
			return ctx.GetMentionedJID(), ctx.GetParticipant()
		}
	}
	if vid := msg.GetVideoMessage(); vid != nil {
		if ctx := vid.GetContextInfo(); ctx != nil {
			return ctx.GetMentionedJID(), ctx.GetParticipant()
		}
	}
	if aud := msg.GetAudioMessage(); aud != nil {
		if ctx := aud.GetContextInfo(); ctx != nil {
			return ctx.GetMentionedJID(), ctx.GetParticipant()
		}
	}
	if doc := msg.GetDocumentMessage(); doc != nil {
		if ctx := doc.GetContextInfo(); ctx != nil {
			return ctx.GetMentionedJID(), ctx.GetParticipant()
		}
	}
	return nil, ""
}

func processIncomingMedia(client *whatsmeow.Client, store *MessageStore, msg *events.Message, mediaType string, logger waLog.Logger) string {
	success, mt, _, path, err := downloadMedia(client, store, msg.Info.ID, msg.Info.Chat.String())
	if !success || err != nil {
		logger.Warnf("[wake] media download failed: %v", err)
		return fmt.Sprintf("(WhatsApp %s could not be downloaded for context.) ", mediaType)
	}
	logger.Infof("[wake] media downloaded: %s -> %s", mt, path)

	switch mt {
	case "audio":
		transcript := runWhisper(path, wakeConfig.MaxMediaWaitSec, logger)
		if transcript == "" {
			return fmt.Sprintf("(Voice note saved at %s; transcription failed.) ", path)
		}
		return fmt.Sprintf("Voice-note transcript (Whisper): %q. Local file: %s. ", transcript, path)
	case "image":
		desc := describeImageWithGemini(path, wakeConfig.MaxMediaWaitSec, logger)
		if desc == "" {
			return fmt.Sprintf("(Image saved at %s; auto-description failed.) ", path)
		}
		return fmt.Sprintf("Image description (Gemini): %q. Local file: %s. ", desc, path)
	case "video":
		return fmt.Sprintf("(Video saved at %s — not auto-described.) ", path)
	case "document":
		return fmt.Sprintf("(Document saved at %s.) ", path)
	}
	return ""
}

func runWhisper(path string, timeoutSec int, logger waLog.Logger) string {
	if wakeConfig.WhisperPython == "" || wakeConfig.WhisperScript == "" {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutSec)*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, wakeConfig.WhisperPython, wakeConfig.WhisperScript, path, "--model", wakeConfig.WhisperModel)
	out, err := cmd.Output()
	if err != nil {
		logger.Warnf("[wake] whisper failed: %v", err)
		return ""
	}
	return strings.TrimSpace(string(out))
}

func describeImageWithGemini(path string, timeoutSec int, logger waLog.Logger) string {
	key := readGeminiKey()
	if key == "" {
		logger.Warnf("[wake] no Gemini API key available")
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	mime := "image/jpeg"
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png":
		mime = "image/png"
	case ".gif":
		mime = "image/gif"
	case ".webp":
		mime = "image/webp"
	}
	body := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"parts": []interface{}{
					map[string]string{"text": "Describe this image briefly (1-2 sentences). What is in it? If there is any text, transcribe it."},
					map[string]interface{}{"inline_data": map[string]string{"mime_type": mime, "data": base64.StdEncoding.EncodeToString(data)}},
				},
			},
		},
	}
	bodyBytes, _ := json.Marshal(body)
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", wakeConfig.GeminiModel, key)
	httpClient := &http.Client{Timeout: time.Duration(timeoutSec) * time.Second}
	resp, err := httpClient.Post(url, "application/json", bytes.NewReader(bodyBytes))
	if err != nil {
		logger.Warnf("[wake] gemini POST failed: %v", err)
		return ""
	}
	defer resp.Body.Close()
	respBytes, _ := io.ReadAll(resp.Body)
	var parsed struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}
	if err := json.Unmarshal(respBytes, &parsed); err != nil {
		return ""
	}
	if len(parsed.Candidates) == 0 || len(parsed.Candidates[0].Content.Parts) == 0 {
		return ""
	}
	return strings.TrimSpace(parsed.Candidates[0].Content.Parts[0].Text)
}

func readGeminiKey() string {
	if wakeConfig.GeminiAPIKeyFile == "" || wakeConfig.GeminiAPIKeyEnv == "" {
		return ""
	}
	data, err := os.ReadFile(wakeConfig.GeminiAPIKeyFile)
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, wakeConfig.GeminiAPIKeyEnv+"=") {
			val := strings.TrimPrefix(line, wakeConfig.GeminiAPIKeyEnv+"=")
			return strings.Trim(val, "\"' ")
		}
	}
	return ""
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}
