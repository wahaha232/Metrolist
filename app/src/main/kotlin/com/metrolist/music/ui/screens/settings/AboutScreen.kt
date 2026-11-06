/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.ui.screens.settings

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.metrolist.music.BuildConfig
import com.metrolist.music.LocalPlayerAwareWindowInsets
import com.metrolist.music.R
import com.metrolist.music.ui.component.IconButton
import com.metrolist.music.ui.component.Material3SettingsGroup
import com.metrolist.music.ui.component.Material3SettingsItem
import com.metrolist.music.ui.utils.backToMain

private const val UPSTREAM_REPO = "https://github.com/MetrolistGroup/Metrolist"
private const val SOURCE_REPO = "https://github.com/wahaha232/Metrolist"
private const val LICENSE_URL = "$SOURCE_REPO/blob/stage2-bluetooth/LICENSE"
private const val THIRD_PARTY_URL = "$SOURCE_REPO/blob/stage2-bluetooth/THIRD_PARTY_LICENSES.md"
private const val BUY_ME_A_COFFEE_URL = "https://buymeacoffee.com/wahaha232z"

private data class LegalLink(
    val labelRes: Int,
    val iconRes: Int,
    val url: String,
)

private val legalLinks = listOf(
    LegalLink(R.string.credits_source_code, R.drawable.github, SOURCE_REPO),
    LegalLink(R.string.credits_license_name, R.drawable.info, LICENSE_URL),
    LegalLink(R.string.credits_third_party, R.drawable.info, THIRD_PARTY_URL),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(navController: NavController) {
    val uriHandler = LocalUriHandler.current
    val windowInsets = LocalPlayerAwareWindowInsets.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(windowInsets.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(
            Modifier.windowInsetsPadding(windowInsets.only(WindowInsetsSides.Top)),
        )
        Spacer(Modifier.height(16.dp))

        ElevatedCard(
            shape = RoundedCornerShape(32.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
            ) {
                Image(
                    painter = painterResource(R.drawable.ic_launcher_foreground),
                    contentDescription = stringResource(R.string.app_name),
                    colorFilter = ColorFilter.tint(
                        color = MaterialTheme.colorScheme.primary,
                        blendMode = BlendMode.SrcIn,
                    ),
                    modifier = Modifier.size(64.dp),
                )

                Spacer(Modifier.width(20.dp))

                Column {
                    Text(
                        text = stringResource(R.string.app_name),
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.onSurface,
                        letterSpacing = (-0.5).sp,
                    )

                    Spacer(Modifier.height(8.dp))

                    Text(
                        text = stringResource(R.string.about_description),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    Spacer(Modifier.height(12.dp))

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        InfoBadge(
                            text = BuildConfig.VERSION_NAME,
                            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
                            contentColor = MaterialTheme.colorScheme.primary,
                        )
                        InfoBadge(
                            text = BuildConfig.ARCHITECTURE.uppercase(),
                            containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f),
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                        if (BuildConfig.DEBUG) {
                            InfoBadge(
                                text = "DEBUG",
                                containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.5f),
                                contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
                            )
                        }
                    }
                }
            }
        }

        if (BUY_ME_A_COFFEE_URL.isNotBlank()) {
            Spacer(Modifier.height(24.dp))
            ElevatedCard(
                shape = RoundedCornerShape(32.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.padding(24.dp)) {
                    Text(
                        text = stringResource(R.string.support_this_build),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = { uriHandler.openUri(BUY_ME_A_COFFEE_URL) },
                        modifier = Modifier.fillMaxWidth(),
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                        ),
                    ) {
                        Icon(
                            painter = painterResource(R.drawable.buymeacoffee),
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                        )
                        Spacer(Modifier.width(12.dp))
                        Text(
                            text = stringResource(R.string.buy_me_a_coffee),
                            fontWeight = FontWeight.ExtraBold,
                            fontSize = 16.sp,
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        Material3SettingsGroup(
            title = stringResource(R.string.credits_source_and_license),
            items = legalLinks.map { link ->
                Material3SettingsItem(
                    icon = painterResource(link.iconRes),
                    title = { Text(stringResource(link.labelRes), fontWeight = FontWeight.SemiBold) },
                    description = if (link.labelRes == R.string.credits_license_name) {
                        { Text(stringResource(R.string.credits_license_desc)) }
                    } else {
                        null
                    },
                    onClick = { uriHandler.openUri(link.url) },
                )
            },
        )

        Spacer(Modifier.height(24.dp))

        Text(
            text = stringResource(R.string.credits_upstream),
            modifier = Modifier
                .fillMaxWidth()
                .clickable { uriHandler.openUri(UPSTREAM_REPO) }
                .padding(vertical = 16.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(48.dp))
    }

    TopAppBar(
        title = { Text(stringResource(R.string.about)) },
        navigationIcon = {
            IconButton(
                onClick = navController::navigateUp,
                onLongClick = navController::backToMain,
            ) {
                Icon(
                    painter = painterResource(R.drawable.arrow_back),
                    contentDescription = stringResource(R.string.cd_back),
                )
            }
        },
    )
}

@Composable
private fun InfoBadge(
    text: String,
    containerColor: Color,
    contentColor: Color,
) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = containerColor,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = contentColor,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
}
