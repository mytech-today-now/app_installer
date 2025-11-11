Add search/filter functionality to 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\app_installer\install-gui.ps1' to help users find applications quickly among 271 options.

Requirements:
- Add search textbox at the top of the application list panel
- Real-time filtering as user types (no search button needed)
- Search should match: application name, category, description
- Case-insensitive search
- Highlight matching text in results
- Show count of filtered results (e.g., "Showing 5 of 271 applications")
- Clear button (X) to reset search
- Preserve checkbox states when filtering
- Category headers should hide if no apps in that category match

Implementation Details:
- Add TextBox control above the CheckedListBox
- Implement TextChanged event handler for real-time filtering
- Create Filter-Applications function that accepts search term
- Use -like operator with wildcards for matching
- Rebuild CheckedListBox with filtered results
- Maintain $script:SelectedApps array across filter changes
- Add Label to show result count
- Follow responsive design patterns from .augment/patterns.md
- Use ASCII-only indicators (no emoji in code)

Testing:
- Search for "chrome" and verify all Chrome-related apps appear
- Search for "browser" and verify category-based filtering works
- Search for partial terms like "fire" to find Firefox
- Verify checkbox states persist when clearing search
- Test with special characters in search term
- Verify performance with 271 applications

Documentation:
- Update README.md with search feature documentation
- Update CHANGELOG.md with version increment (1.3.8)
- Add screenshot showing search functionality
- Document search syntax and capabilities