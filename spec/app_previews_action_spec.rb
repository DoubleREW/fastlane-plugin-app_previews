describe Fastlane::Actions::AppPreviewsAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The app_previews plugin is working!")

      Fastlane::Actions::AppPreviewsAction.run(nil)
    end
  end
end
